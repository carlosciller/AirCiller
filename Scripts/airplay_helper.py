#!/usr/bin/env python3
"""Small JSON bridge between AirCiller and pyatv.

Only stdout is used for machine-readable events. Diagnostic logging goes to stderr.
"""

import argparse
import asyncio
from contextlib import asynccontextmanager
import json
import logging
from pathlib import Path
import plistlib
import sys
from typing import Any, Dict, Mapping, Optional
from uuid import getnode, uuid4

import pyatv
from pyatv import exceptions
from pyatv.auth.hap_channel import setup_channel
from pyatv.const import Protocol
from pyatv.protocols.airplay.auth import extract_credentials, verify_connection
from pyatv.protocols.airplay.channels import EventChannel
from pyatv.protocols.airplay.utils import AirPlayMajorVersion, get_protocol_version
from pyatv.protocols.raop.protocols import StreamContext, TimingServer
from pyatv.protocols.raop.protocols.airplayv2 import AirPlayV2
from pyatv.settings import AirPlayVersion
from pyatv.support.http import HttpResponse, decode_bplist_from_body, http_connect
from pyatv.support import rtsp as rtsp_support
from pyatv.support.rtsp import RtspSession


logging.basicConfig(stream=sys.stderr, level=logging.WARNING)


# Modern tvOS uses the AirPlay 2 video queue protocol. It first creates a
# type-130 remote-control session and then accepts queue commands at /command.
AIRPLAY_CONTROL_CLIENT_TYPE = "A6B27562-B43A-4F2D-B75F-82391E250194"
AIRPLAY_SESSION_HEADERS = {
    "User-Agent": "AirPlay/960.13.1",
}
# pyatv 0.18 still sends AirPlay/550.10 on RTSP SETUP and RECORD. Keep the
# whole modern video session on the same sender generation as queue commands.
rtsp_support.USER_AGENT = AIRPLAY_SESSION_HEADERS["User-Agent"]
AIRPLAY_COMMAND_HEADERS = {
    **AIRPLAY_SESSION_HEADERS,
    "Content-Type": "application/x-apple-binary-plist",
}
EVENTS_SALT = "Events-Salt"
EVENTS_WRITE_INFO = "Events-Write-Encryption-Key"
EVENTS_READ_INFO = "Events-Read-Encryption-Key"
MR_NOW_PLAYING_PREFIX = "kMRMediaRemoteNowPlayingInfo"
MR_MEDIA_TYPE_VIDEO = "kMRMediaRemoteNowPlayingInfoTypeVideo"
MAX_ARTWORK_BYTES = 2 * 1024 * 1024
FEEDBACK_INTERVAL_SECONDS = 2.0
MAX_CONSECUTIVE_FEEDBACK_FAILURES = 3


class AirPlaySessionRejectedError(exceptions.PlaybackError):
    """The HAP credential worked, but tvOS rejected a later video-session step."""


def sender_device_id() -> str:
    value = getnode()
    return ":".join(f"{(value >> shift) & 0xFF:02X}" for shift in range(40, -1, -8))


def airplay_time_value(seconds: float) -> Dict[str, int]:
    return {
        "epoch": 0,
        "flags": 1,
        "timescale": 1,
        "value": int(max(0.0, seconds)),
    }


def airplay_command_body(command: Dict[str, Any]) -> bytes:
    inner = plistlib.dumps(command, fmt=plistlib.FMT_BINARY, sort_keys=False)
    return plistlib.dumps(
        {"params": {"data": inner}},
        fmt=plistlib.FMT_BINARY,
        sort_keys=False,
    )


def read_artwork(path: str) -> bytes:
    if not path:
        return b""
    try:
        data = Path(path).read_bytes()
    except OSError as error:
        logging.warning("No se pudo leer el icono de AirCiller: %s", error)
        return b""
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        logging.warning("La carátula de AirCiller no es un PNG válido")
        return b""
    if len(data) > MAX_ARTWORK_BYTES:
        logging.warning("La carátula de AirCiller supera el límite de 2 MB")
        return b""
    return data


def now_playing_info(
    title: str,
    duration: float,
    position: float,
    artwork: bytes = b"",
) -> Dict[str, Any]:
    """Build the MediaRemote dictionary used by current AirPlay 2 senders."""
    info: Dict[str, Any] = {
        f"{MR_NOW_PLAYING_PREFIX}Title": title,
        f"{MR_NOW_PLAYING_PREFIX}Album": "AirCiller",
        f"{MR_NOW_PLAYING_PREFIX}PlaybackRate": 1.0,
        f"{MR_NOW_PLAYING_PREFIX}DefaultPlaybackRate": 1.0,
        f"{MR_NOW_PLAYING_PREFIX}MediaType": MR_MEDIA_TYPE_VIDEO,
    }
    if duration > 0:
        info[f"{MR_NOW_PLAYING_PREFIX}Duration"] = duration
        info[f"{MR_NOW_PLAYING_PREFIX}ElapsedTime"] = max(0.0, position)
    if artwork:
        info[f"{MR_NOW_PLAYING_PREFIX}ArtworkData"] = artwork
        info[f"{MR_NOW_PLAYING_PREFIX}ArtworkMIMEType"] = "image/png"
        info[f"{MR_NOW_PLAYING_PREFIX}ArtworkDataWidth"] = 1024
        info[f"{MR_NOW_PLAYING_PREFIX}ArtworkDataHeight"] = 1024
    return info


def now_playing_command(
    title: str,
    duration: float,
    position: float,
    artwork: bytes = b"",
) -> Dict[str, Any]:
    return {
        "type": "updateMRNowPlayingInfo",
        "params": {
            "type": "npi-text",
            "params": now_playing_info(title, duration, position, artwork),
            "mergePolicy": "replace",
        },
    }


class AirCillerEventChannel(EventChannel):
    """Event channel that preserves the playback messages tvOS pushes."""

    listener = None

    def handle_received(self) -> None:
        while self.buffer:
            try:
                request, _, self.buffer = self.parse_request(self.buffer)
                if request is None:
                    break

                if self.listener is not None:
                    body = request.body if isinstance(request.body, bytes) else b""
                    if body.startswith(b"bplist00"):
                        outer = plistlib.loads(body)
                        if isinstance(outer, dict):
                            data = outer.get("params", {}).get("data")
                            event = plistlib.loads(data) if isinstance(data, bytes) else outer
                            if isinstance(event, dict):
                                self.listener.handle_event(event)

                headers = {"Content-Length": "0", "Audio-Latency": "0"}
                if "Server" in request.headers:
                    headers["Server"] = request.headers["Server"]
                if "CSeq" in request.headers:
                    headers["CSeq"] = request.headers["CSeq"]
                self.send(
                    self.format_response(
                        HttpResponse(
                            request.protocol,
                            request.version,
                            200,
                            "OK",
                            headers,
                            b"",
                        )
                    )
                )
            except Exception:
                logging.exception("No se pudo interpretar un evento AirPlay 2")


class AirCillerAirPlayV2(AirPlayV2):
    """AirPlay 2 video queue transport compatible with current tvOS."""

    def __init__(self, context: StreamContext, rtsp: RtspSession) -> None:
        super().__init__(context, rtsp)
        self.control_stream_id: Optional[str] = None
        self.current_item_uuid: Optional[str] = None
        self.device_id = sender_device_id()
        self._media_ended = asyncio.Event()
        self._terminal_reason: Optional[str] = None
        self._did_emit_playing = False
        self._receiver_is_playing = False
        self._control_lock = asyncio.Lock()
        self._metadata_title = ""
        self._metadata_duration = 0.0
        self._metadata_position = 0.0
        self._metadata_artwork = b""
        self._metadata_task: Optional[asyncio.Task] = None

    async def _setup_base(self, timing_server_port: int) -> None:
        # Video uses PTP. An NTP setup is accepted by tvOS but receives no
        # playback events and the picture collapses after roughly 20 seconds.
        if self._verifier is None:
            emit("phase", message="Verificando credencial HAP")
            self._verifier = await verify_connection(
                self.context.credentials, self.rtsp.connection
            )
            emit("phase", message="Credencial HAP aceptada")

        local_ip = self.rtsp.connection.local_ip
        peer = {
            "ID": self.uuid.upper(),
            "Addresses": [local_ip],
            "DeviceType": 0,
            "SupportsClockPortMatchingOverride": True,
        }
        emit("phase", message="Abriendo sesión PTP AirPlay 2")
        try:
            setup_resp = await self.rtsp.setup(
                body={
                "timingProtocol": "PTP",
                "timingPeerInfo": peer,
                "timingPeerList": [peer],
                "sessionUUID": str(uuid4()).upper(),
                "sessionCorrelationUUID": self.uuid.upper(),
                "updateSessionRequest": False,
                "statsCollectionEnabled": False,
                "isMultiSelectAirPlay": False,
                "deviceID": self.device_id,
                "macAddress": self.device_id,
                "model": "Mac16,8",
                "name": "AirCiller",
                "osName": "Mac OS X",
                "osVersion": "27.0",
                "osBuildVersion": "26A5416b",
                "sourceVersion": "960.13.1",
                },
            )
        except exceptions.AuthenticationError as error:
            raise AirPlaySessionRejectedError(
                "tvOS aceptó la credencial, pero rechazó SETUP PTP de la sesión de vídeo."
            ) from error
        emit("phase", message="Sesión PTP aceptada")
        response = decode_bplist_from_body(setup_resp)
        event_port = int(response.get("eventPort", 0))
        if event_port <= 0:
            raise exceptions.NotSupportedError(
                "El Apple TV no devolvió el canal de eventos de AirPlay 2."
            )

        retries = 5
        transport = None
        protocol = None
        while transport is None:
            try:
                transport, protocol = await setup_channel(
                    AirCillerEventChannel,
                    self._verifier,
                    self.rtsp.connection.remote_ip,
                    event_port,
                    EVENTS_SALT,
                    EVENTS_READ_INFO,
                    EVENTS_WRITE_INFO,
                )
            except ConnectionRefusedError:
                retries -= 1
                if retries == 0:
                    raise
                await asyncio.sleep(0.25)
        protocol.listener = self
        self.event_channel = transport
        emit(
            "phase",
            message="Sesión AirPlay 2 autenticada y canal de eventos abierto",
        )

    async def ensure_control_stream(self) -> str:
        if self.control_stream_id:
            return self.control_stream_id

        channel_id = str(uuid4()).upper()

        try:
            response = await self.rtsp.setup(
                body={
                "streams": [
                    {
                        "clientUUID": str(uuid4()).upper(),
                        "clientTypeUUID": AIRPLAY_CONTROL_CLIENT_TYPE,
                        "controlType": 1,
                        "channelID": channel_id,
                        "type": 130,
                    }
                ]
                },
            )
        except exceptions.AuthenticationError as error:
            raise AirPlaySessionRejectedError(
                "tvOS aceptó la sesión PTP, pero rechazó el stream de control AirPlay 2."
            ) from error
        if response.code >= 400:
            raise exceptions.PlaybackError(
                f"El Apple TV rechazó el stream de control AirPlay 2 (HTTP {response.code})."
            )
        decoded = decode_bplist_from_body(response)
        streams = decoded.get("streams", [])
        stream_id = streams[0].get("streamID") if streams else None
        if stream_id is None:
            raise exceptions.PlaybackError(
                "El Apple TV no asignó un streamID a la cola de reproducción."
            )
        self.control_stream_id = str(stream_id)
        emit("phase", message="Stream de control AirPlay 2 creado")
        return self.control_stream_id

    async def send_queue_command(self, command: Dict[str, Any]):
        stream_id = await self.ensure_control_stream()
        headers = {
            **AIRPLAY_COMMAND_HEADERS,
            "X-Apple-StreamID": stream_id,
        }
        try:
            async with self._control_lock:
                return await self.rtsp.connection.post(
                    "/command",
                    headers=headers,
                    body=airplay_command_body(command),
                    allow_error=True,
                )
        except exceptions.AuthenticationError as error:
            raise AirPlaySessionRejectedError(
                "tvOS abrió el control AirPlay 2, pero rechazó la orden de reproducción."
            ) from error

    async def _feedback_task_loop(self) -> None:
        # /feedback and /command share one RTSP connection. Serializing them
        # prevents tvOS from closing the session when a remote action or a
        # metadata update lands while feedback is in flight.
        consecutive_failures = 0
        while True:
            try:
                async with self._control_lock:
                    await self.rtsp.feedback()
            except asyncio.CancelledError:
                raise
            except Exception as error:
                consecutive_failures += 1
                logging.warning(
                    "Feedback AirPlay 2 fallido (%d/%d): %s",
                    consecutive_failures,
                    MAX_CONSECUTIVE_FEEDBACK_FAILURES,
                    error,
                )
                if consecutive_failures >= MAX_CONSECUTIVE_FEEDBACK_FAILURES:
                    # Current tvOS can close the RTSP /feedback path while the
                    # independent event channel and the HTTP media transfer
                    # continue normally. Treating that as the end of playback
                    # tears down a healthy stream. The macOS side verifies the
                    # real start separately from receiver HTTP traffic.
                    emit(
                        "warning",
                        message=(
                            "El canal de feedback dejó de responder; AirCiller "
                            "mantendrá el stream mientras siga activo el Apple TV."
                        ),
                    )
                    return
            else:
                consecutive_failures = 0
            await asyncio.sleep(FEEDBACK_INTERVAL_SECONDS)

    async def send_now_playing_metadata(
        self,
        title: str,
        duration: float,
        position: float,
        artwork: bytes = b"",
    ):
        return await self.send_queue_command(
            now_playing_command(title, duration, position, artwork)
        )

    def _schedule_now_playing_metadata(self) -> None:
        if not self._metadata_title or self._metadata_task is not None:
            return
        self._metadata_task = asyncio.create_task(self._publish_now_playing_metadata())

    async def _publish_now_playing_metadata(self) -> None:
        try:
            response = await self.send_now_playing_metadata(
                self._metadata_title,
                self._metadata_duration,
                self._metadata_position,
                self._metadata_artwork,
            )
            if response.code < 400:
                emit("phase", message="Título y carátula enviados a Ahora suena")
            else:
                emit(
                    "warning",
                    message=(
                        "El Apple TV no aceptó los metadatos de Ahora suena; "
                        "la película seguirá reproduciéndose."
                    ),
                )
        except asyncio.CancelledError:
            raise
        except Exception as error:
            logging.warning("Metadatos de Ahora suena rechazados: %s", error)
            emit(
                "warning",
                message=(
                    "No se pudo publicar la carátula en Ahora suena; "
                    "la película seguirá reproduciéndose."
                ),
            )

    async def set_rate(self, value: float):
        return await self.send_queue_command(
            {"type": "setRate", "rate": 1 if value > 0 else 0}
        )

    async def seek(self, position: float):
        if not self.current_item_uuid:
            raise exceptions.InvalidStateError("no hay una película activa")
        return await self.send_queue_command(
            {
                "type": "seek",
                "kind": "request",
                "time": airplay_time_value(position),
                "item": {"uuid": self.current_item_uuid},
            }
        )

    async def stop_playback(self):
        if not self.current_item_uuid:
            return None
        return await self.send_queue_command(
            {
                "type": "removePlayQueueItem",
                "item": {"uuid": self.current_item_uuid},
            }
        )

    @staticmethod
    def _event_value(event: Mapping[str, Any], *keys: str) -> Any:
        def find(mapping: Mapping[str, Any], wanted: str) -> Any:
            for key, value in mapping.items():
                if str(key).casefold() == wanted:
                    return value
            for value in mapping.values():
                if isinstance(value, Mapping):
                    nested = find(value, wanted)
                    if nested is not None:
                        return nested
            return None

        for key in keys:
            value = find(event, key.casefold())
            if value is not None:
                return value
        return None

    @staticmethod
    def _time_number(value: Any) -> Optional[float]:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if not isinstance(value, Mapping):
            return None
        raw_value = AirCillerAirPlayV2._event_value(value, "value", "seconds")
        if isinstance(raw_value, bool) or not isinstance(raw_value, (int, float)):
            return None
        timescale = AirCillerAirPlayV2._event_value(value, "timescale")
        if isinstance(timescale, (int, float)) and not isinstance(timescale, bool):
            return float(raw_value) / float(timescale) if timescale else None
        return float(raw_value)

    @classmethod
    def _event_time(cls, event: Mapping[str, Any], *keys: str) -> Optional[float]:
        return cls._time_number(cls._event_value(event, *keys))

    @staticmethod
    def _normalized_state(value: Any) -> str:
        if isinstance(value, bool):
            return "playing" if value else "paused"
        if isinstance(value, (int, float)):
            return {
                1: "playing",
                2: "paused",
                3: "stopped",
                4: "paused",
                5: "seeking",
            }.get(int(value), "")
        compact = "".join(character for character in str(value).casefold() if character.isalnum())
        aliases = {
            "play": "playing",
            "started": "playing",
            "resume": "playing",
            "resumed": "playing",
            "pause": "paused",
            "interrupted": "paused",
            "buffering": "loading",
            "stalling": "loading",
            "itemplayedtoend": "ended",
            "ended": "ended",
        }
        return aliases.get(compact, compact)

    def handle_event(self, event: Mapping[str, Any]) -> None:
        kind = str(event.get("type", event.get("eventType", ""))).casefold()
        state_value = self._event_value(event, "playbackState", "state", "name")
        name = self._normalized_state(state_value)
        duration = self._event_time(event, "duration", "totalTime")
        position = self._event_time(
            event, "position", "currentTime", "elapsedTime", "playbackPosition"
        )
        rate = self._event_time(event, "rate", "playbackRate")

        is_playback_event = kind in {
            "playbackstate",
            "playbackstatechanged",
            "playbackstatus",
            "playbackstatuschanged",
        } or name in {"playing", "paused", "loading", "stopped", "seeking", "ended"}
        if not name and rate is not None:
            name = "playing" if rate > 0 else "paused"
            is_playback_event = True

        if is_playback_event:
            if name == "playing":
                was_playing = self._receiver_is_playing
                self._receiver_is_playing = True
                self._schedule_now_playing_metadata()
                if not self._did_emit_playing:
                    self._did_emit_playing = True
                    emit("playing", duration=duration, position=position, playing=True)
                elif not was_playing:
                    emit(
                        "resumed",
                        duration=duration,
                        position=position,
                        playing=True,
                        source="receiver",
                    )
                else:
                    emit("status", duration=duration, position=position, playing=True)
            elif name == "loading":
                emit("waiting")
            elif name == "paused":
                self._receiver_is_playing = False
                emit(
                    "paused",
                    duration=duration,
                    position=position,
                    playing=False,
                    source="receiver",
                )
            elif name == "stopped" and self._did_emit_playing:
                self._receiver_is_playing = False
                self._terminal_reason = "stopped"
                self._media_ended.set()
            elif name == "ended" and self._did_emit_playing:
                self._receiver_is_playing = False
                self._terminal_reason = "ended"
                self._media_ended.set()
            elif position is not None or duration is not None:
                emit(
                    "status",
                    duration=duration,
                    position=position,
                    playing=self._receiver_is_playing,
                )
        elif kind == "notification":
            notification = self._normalized_state(
                self._event_value(event, "name", "notification", "event")
            )
            if notification == "ended" and self._did_emit_playing:
                self._receiver_is_playing = False
                self._terminal_reason = "ended"
                self._media_ended.set()
        elif position is not None or duration is not None:
            emit(
                "status",
                duration=duration,
                position=position,
                playing=self._receiver_is_playing,
            )

    async def wait_for_media_end(self) -> str:
        await self._media_ended.wait()
        return self._terminal_reason or "ended"

    def teardown(self) -> None:
        if self._metadata_task is not None:
            self._metadata_task.cancel()
            self._metadata_task = None
        super().teardown()

    async def play_url(
        self,
        timing_server_port: int,
        url: str,
        position: float = 0.0,
        duration: float = 0.0,
        title: str = "",
        artwork: bytes = b"",
    ):
        # Pair verify -> PTP video session -> RECORD -> RCS -> queue commands ->
        # feedback. tvOS silently closes the shared connection if feedback is
        # already in flight while /command is being issued.
        if self._verifier is None:
            self._verifier = await verify_connection(
                self.context.credentials, self.rtsp.connection
            )
        await self._setup_base(timing_server_port)
        emit("phase", message="Activando la sesión de vídeo")
        try:
            await self.rtsp.record()
        except exceptions.AuthenticationError as error:
            raise AirPlaySessionRejectedError(
                "tvOS aceptó SETUP PTP, pero rechazó RECORD para activar el vídeo."
            ) from error
        emit("phase", message="Sesión de vídeo activa")
        await self.ensure_control_stream()

        self._metadata_title = title
        self._metadata_duration = duration
        self._metadata_position = position
        self._metadata_artwork = artwork

        self.current_item_uuid = str(uuid4()).upper()
        item = {
            "uuid": self.current_item_uuid,
            "Content-Location": url,
            "Start-Position": airplay_time_value(position),
            "mediaType": "file",
            "IsTLSEnabled": url.startswith("https://"),
            "playbackRestrictions": 0,
            "referenceRestrictions": 2,
            "supportsIntegratedTimeline": False,
            "snapTimeToPausePlayback": False,
            "clientBundleID": "local.carlosciller.AirCiller",
            "clientProcName": "AirCiller",
            "playerLoggingID": "P/AIRC",
            "playerItemLoggingID": "I/AIRCILLER.01",
        }
        if title:
            item["title"] = title
        if duration > 0:
            item["duration"] = duration
        response = await self.send_queue_command(
            {"type": "insertPlayQueueItem", "item": item}
        )
        if response.code >= 400:
            return response
        emit("phase", message="Película insertada en la cola del Apple TV")

        property_response = await self.send_queue_command(
            {
                "type": "setProperty",
                "property": "isInterestedInDateRange",
                "value": True,
                "item": {"uuid": self.current_item_uuid},
            }
        )
        if property_response.code >= 400:
            return property_response

        rate_response = await self.set_rate(1.0)
        if rate_response.code < 400:
            emit("phase", message="Inicio solicitado a la cola AirPlay 2")
            await self.start_feedback()
        return rate_response if rate_response.code >= 400 else response


def emit(event: str, **payload: Any) -> None:
    print(json.dumps({"event": event, **payload}, ensure_ascii=False), flush=True)


def plain_error(error: BaseException) -> str:
    text = str(error).strip()
    if isinstance(error, exceptions.AuthenticationError) or (
        isinstance(error, exceptions.HttpError) and getattr(error, "status_code", None) == 470
    ):
        return (
            "El Apple TV exige autenticación o emparejamiento para este Mac. "
            f"Detalle técnico: {text or error.__class__.__name__}."
        )
    if isinstance(error, (TimeoutError, asyncio.TimeoutError)):
        return "El Apple TV no respondió a tiempo. Comprueba que siga encendido y en la misma red."
    if isinstance(error, exceptions.ConnectionFailedError):
        return "No se pudo abrir la conexión AirPlay con el Apple TV."
    if is_connection_lost_error(error):
        return "Se perdió el canal de control con el Apple TV."
    return text or error.__class__.__name__


def error_reason(error: BaseException) -> str:
    if isinstance(error, exceptions.AuthenticationError) or (
        isinstance(error, exceptions.HttpError)
        and getattr(error, "status_code", None) == 470
    ):
        return "authorizationRequired"
    if isinstance(error, (TimeoutError, asyncio.TimeoutError)):
        return "timeout"
    if isinstance(error, exceptions.ConnectionFailedError) or is_connection_lost_error(error):
        return "connectionFailed"
    if isinstance(error, exceptions.PlaybackError):
        return "playbackRejected"
    return "unexpected"


def is_connection_lost_error(error: BaseException) -> bool:
    if isinstance(error, (exceptions.ConnectionFailedError, ConnectionError, BrokenPipeError)):
        return True
    compact = str(error).casefold()
    return any(
        marker in compact
        for marker in (
            "not connected to remote",
            "connection closed",
            "connection lost",
            "broken pipe",
        )
    )


async def discover(timeout: int, address: Optional[str] = None):
    hosts = [address] if address else None
    devices = await pyatv.scan(
        asyncio.get_running_loop(),
        timeout=timeout,
        protocol=Protocol.AirPlay,
        hosts=hosts,
    )
    return [device for device in devices if device.get_service(Protocol.AirPlay)]


def describe_device(config) -> Dict[str, Any]:
    service = config.get_service(Protocol.AirPlay)
    properties = service.properties
    try:
        protocol_version = get_protocol_version(service, AirPlayVersion.Auto)
        protocol_name = "AirPlay 2" if protocol_version == AirPlayMajorVersion.AirPlayV2 else "AirPlay 1"
    except Exception:
        protocol_name = "AirPlay"

    return {
        "id": service.identifier or str(config.address),
        "name": config.name,
        "address": str(config.address),
        "port": service.port,
        "model": properties.get("model", "Apple TV"),
        "osVersion": properties.get("osvers", ""),
        "protocolVersion": protocol_name,
        "pairing": getattr(service.pairing, "name", str(service.pairing)),
        "requiresPassword": service.requires_password,
        "features": properties.get("features", properties.get("ft", "")),
        "authenticationType": extract_credentials(service).type.name,
    }


async def scan_command(args) -> int:
    devices = await discover(args.timeout, args.address)
    emit("devices", devices=[describe_device(device) for device in devices])
    return 0


async def connect_stdin() -> asyncio.StreamReader:
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin)
    return reader


async def pair_command(args) -> int:
    devices = await discover(args.timeout, args.address)
    if not devices:
        raise RuntimeError(f"No se encontró ningún servicio AirPlay en {args.address}.")
    config = devices[0]
    emit("pairingStarted", device=describe_device(config))
    pairing = await pyatv.pair(
        config,
        Protocol.AirPlay,
        asyncio.get_running_loop(),
        name="AirCiller",
    )
    credentials = ""
    try:
        await pairing.begin()
        emit("pinRequired", deviceName=config.name)
        reader = await connect_stdin()
        try:
            request = await asyncio.wait_for(read_stdin_line(reader), timeout=180)
        except asyncio.TimeoutError as error:
            raise exceptions.PairingError(
                "El código de autorización ha caducado. Vuelve a intentarlo para mostrar uno nuevo."
            ) from error
        pin = str((request or {}).get("pin", ""))
        if not pin.isdigit() or len(pin) != 4:
            raise exceptions.PairingError("El código debe tener cuatro cifras.")
        pairing.pin(int(pin))
        await pairing.finish()
        if not pairing.has_paired or not pairing.service.credentials:
            raise exceptions.PairingError("El Apple TV no confirmó el emparejamiento.")
        credentials = pairing.service.credentials
    finally:
        await pairing.close()

    # Pair-Setup can report success before tvOS has made the new HAP identity
    # usable. Verify it on a fresh connection before AirCiller stores it or
    # starts preparing media. This also turns the tvOS 27 pairing regression
    # into one bounded error instead of a PIN/VOD retry loop.
    service = config.get_service(Protocol.AirPlay)
    service.credentials = credentials
    verification_error: Optional[BaseException] = None
    for delay in (0.35, 0.8, 1.6):
        await asyncio.sleep(delay)
        connection = await http_connect(str(config.address), service.port)
        try:
            await verify_connection(extract_credentials(service), connection)
            emit("paired", credentials=credentials)
            return 0
        except BaseException as error:
            verification_error = error
        finally:
            connection.close()

    raise exceptions.AuthenticationError(
        "El Apple TV aceptó el código, pero rechazó la credencial nueva al verificarla"
        + (f": {verification_error}" if verification_error else ".")
    )


@asynccontextmanager
async def timing_server(rtsp: RtspSession):
    local_address = (rtsp.connection.local_ip, 0)
    transport, server = await asyncio.get_running_loop().create_datagram_endpoint(
        TimingServer, local_addr=local_address
    )
    try:
        yield server
    finally:
        transport.close()


async def read_stdin_line(reader: asyncio.StreamReader) -> Optional[Dict[str, Any]]:
    line = await reader.readline()
    if not line:
        return {"command": "stop"}
    try:
        value = json.loads(line.decode("utf-8"))
        return value if isinstance(value, dict) else None
    except (UnicodeDecodeError, json.JSONDecodeError):
        emit("warning", message="AirCiller envió una orden de control no válida.")
        return None


async def send_rate(rtsp: RtspSession, stream_protocol, is_v2: bool, value: float) -> None:
    if is_v2 and hasattr(stream_protocol, "set_rate"):
        response = await stream_protocol.set_rate(value)
        if response.code >= 400:
            raise exceptions.PlaybackError(
                f"Apple TV rechazó el cambio de reproducción (HTTP {response.code})"
            )
        return
    path = f"/rate?value={value:.6f}"
    if is_v2:
        await rtsp.exchange("POST", uri=path)
    else:
        await rtsp.connection.post(path)


async def send_seek(rtsp: RtspSession, stream_protocol, is_v2: bool, position: float) -> None:
    if is_v2 and hasattr(stream_protocol, "seek"):
        response = await stream_protocol.seek(position)
        if response.code >= 400:
            raise exceptions.PlaybackError(
                f"Apple TV rechazó el salto (HTTP {response.code})"
            )
        return
    path = f"/scrub?position={max(0.0, position):.6f}"
    if is_v2:
        await rtsp.exchange("POST", uri=path)
    else:
        await rtsp.connection.post(path)


async def playback_loop(
    rtsp: RtspSession,
    stream_protocol,
    is_v2: bool,
    reader: asyncio.StreamReader,
) -> None:
    pending_line = asyncio.create_task(read_stdin_line(reader))
    media_end = (
        asyncio.create_task(stream_protocol.wait_for_media_end())
        if is_v2 and hasattr(stream_protocol, "wait_for_media_end")
        else None
    )

    try:
        while True:
            waiters = {pending_line}
            if media_end is not None:
                waiters.add(media_end)
            done, _ = await asyncio.wait(waiters, return_when=asyncio.FIRST_COMPLETED)

            if media_end is not None and media_end in done:
                terminal_reason = media_end.result()
                if terminal_reason:
                    if terminal_reason == "disconnected":
                        emit(
                            "error",
                            message="Se perdió el canal de control con el Apple TV.",
                            reason="connectionFailed",
                        )
                    else:
                        emit(terminal_reason if isinstance(terminal_reason, str) else "ended")
                    return
                media_end = None

            if pending_line in done:
                command = pending_line.result()
                pending_line = asyncio.create_task(read_stdin_line(reader))
                if not command:
                    continue
                name = str(command.get("command", ""))
                if name == "stop":
                    if is_v2 and hasattr(stream_protocol, "stop_playback"):
                        response = await stream_protocol.stop_playback()
                        if response is not None and response.code >= 400:
                            emit("warning", message="El Apple TV cerró la sesión antes de confirmar la parada.")
                    emit("stopped")
                    return
                if name == "pause":
                    await send_rate(rtsp, stream_protocol, is_v2, 0.0)
                    emit("paused", source="command")
                    continue
                if name == "resume":
                    await send_rate(rtsp, stream_protocol, is_v2, 1.0)
                    emit("resumed", source="command")
                    continue
                if name == "seek":
                    position = float(command.get("position", 0.0))
                    await send_seek(rtsp, stream_protocol, is_v2, position)
                    emit("seeked", position=position, source="command")
                    continue
    finally:
        pending_line.cancel()
        if media_end is not None:
            media_end.cancel()
        stream_protocol.teardown()


async def play_command(args) -> int:
    devices = await discover(args.timeout, args.address)
    if not devices:
        raise RuntimeError(
            f"No se encontró ningún servicio AirPlay en {args.address}."
        )
    config = devices[0]
    service = config.get_service(Protocol.AirPlay)
    emit("connecting", device=describe_device(config))

    reader = await connect_stdin()
    credential_message = await read_stdin_line(reader)
    credentials = str((credential_message or {}).get("credentials", ""))
    if credentials:
        service.credentials = credentials

    connection = await http_connect(str(config.address), service.port)
    rtsp = RtspSession(connection)
    context = StreamContext()
    context.credentials = extract_credentials(service)
    context.password = service.password

    version = get_protocol_version(service, AirPlayVersion.Auto)
    if version != AirPlayMajorVersion.AirPlayV2:
        raise exceptions.NotSupportedError(
            "Este receptor no anuncia vídeo AirPlay 2; AirCiller no utilizará un protocolo antiguo."
        )
    is_v2 = True
    stream_protocol = AirCillerAirPlayV2(context, rtsp)

    try:
        async with timing_server(rtsp) as server:
            response = await stream_protocol.play_url(
                server.port,
                args.url,
                args.position,
                args.duration,
                args.title,
                read_artwork(args.artwork),
            )
            if response.code >= 400:
                if response.code == 470:
                    raise exceptions.AuthenticationError(
                        f"Apple TV devolvió HTTP {response.code}"
                    )
                raise exceptions.PlaybackError(
                    f"Apple TV rechazó la orden AirPlay 2 (HTTP {response.code})"
                )
            emit("accepted", protocol="AirPlay 2" if is_v2 else "AirPlay 1")
            await playback_loop(rtsp, stream_protocol, is_v2, reader)
    finally:
        connection.close()
    return 0


async def authorize_command(args) -> int:
    """Verify the saved AirPlay credential without preparing or loading media."""
    devices = await discover(args.timeout, args.address)
    if not devices:
        raise RuntimeError(
            f"No se encontró ningún servicio AirPlay en {args.address}."
        )
    config = devices[0]
    service = config.get_service(Protocol.AirPlay)
    emit("connecting", device=describe_device(config))

    reader = await connect_stdin()
    credential_message = await read_stdin_line(reader)
    credentials = str((credential_message or {}).get("credentials", ""))
    # When the receiver advertises modern transient HAP, pyatv can authorize
    # the AirPlay 2 session without creating or persisting a PIN credential.
    # Only override that automatic mode when AirCiller already has a saved
    # credential for a receiver that genuinely requires one.
    if credentials:
        service.credentials = credentials

    connection = await http_connect(str(config.address), service.port)
    try:
        await verify_connection(extract_credentials(service), connection)
        emit("authorized", device=describe_device(config))
    finally:
        connection.close()
    return 0


async def async_main(args) -> int:
    if args.command == "scan":
        return await scan_command(args)
    if args.command == "authorize":
        return await authorize_command(args)
    if args.command == "play":
        return await play_command(args)
    if args.command == "pair":
        return await pair_command(args)
    emit("version", version="0.18.0")
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="AirCillerAirPlay")
    subparsers = parser.add_subparsers(dest="command", required=True)

    version = subparsers.add_parser("version")
    version.set_defaults(command="version")

    scan = subparsers.add_parser("scan")
    scan.add_argument("--timeout", type=int, default=5)
    scan.add_argument("--address")

    authorize = subparsers.add_parser("authorize")
    authorize.add_argument("--address", required=True)
    authorize.add_argument("--timeout", type=int, default=5)

    play = subparsers.add_parser("play")
    play.add_argument("--address", required=True)
    play.add_argument("--url", required=True)
    play.add_argument("--position", type=float, default=0.0)
    play.add_argument("--duration", type=float, default=0.0)
    play.add_argument("--title", default="")
    play.add_argument("--artwork", default="")
    play.add_argument("--timeout", type=int, default=5)

    pair = subparsers.add_parser("pair")
    pair.add_argument("--address", required=True)
    pair.add_argument("--timeout", type=int, default=5)
    return parser


def main() -> int:
    args = make_parser().parse_args()
    try:
        return asyncio.run(async_main(args))
    except KeyboardInterrupt:
        return 130
    except BaseException as error:  # Emit one understandable terminal event.
        emit(
            "error",
            message=plain_error(error),
            technical=repr(error),
            reason=error_reason(error),
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
