#!/usr/bin/env python3

import asyncio
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import plistlib
from unittest.mock import patch
from uuid import UUID


PROJECT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "airciller_airplay_helper", PROJECT / "Scripts" / "airplay_helper.py"
)
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class FakeResponse:
    def __init__(self, body=None, code=200):
        self.code = code
        self.body = plistlib.dumps(body or {}, fmt=plistlib.FMT_BINARY)
        self.headers = {"content-type": "application/x-apple-binary-plist"}


class FakeConnection:
    def __init__(self, events):
        self.events = events
        self.requests = []
        self.detailed_requests = []
        self.closed = False
        self.local_ip = "192.0.2.5"
        self.remote_ip = "192.0.2.20"

    async def get(self, path, allow_error=False):
        self.events.append(("GET", path))
        self.requests.append(("GET", path))
        return FakeResponse({"psi": "A1B2C3"})

    async def post(self, path, headers=None, body=None, allow_error=False):
        self.events.append(("POST", path))
        self.requests.append(("POST", path))
        self.detailed_requests.append(
            {"path": path, "headers": headers or {}, "body": body}
        )
        return FakeResponse()

    def close(self):
        self.closed = True


class FakeRTSP:
    def __init__(self):
        self.events = []
        self.connection = FakeConnection(self.events)
        self.detailed_requests = []

    async def setup(self, headers=None, body=None):
        self.events.append(("RTSP", "SETUP"))
        self.detailed_requests.append(
            {"method": "SETUP", "headers": headers or {}, "body": body}
        )
        if isinstance(body, dict) and body.get("streams"):
            return FakeResponse({"streams": [{"streamID": 73}]})
        return FakeResponse({"eventPort": 49152})

    async def record(self, headers=None, body=None):
        self.events.append(("RTSP", "RECORD"))
        return FakeResponse()


class FakeProtocol:
    def __init__(self):
        self.did_teardown = False
        self.end_event = asyncio.Event()
        self.rates = []
        self.seeks = []
        self.stop_calls = 0

    async def wait_for_media_end(self):
        await self.end_event.wait()
        return True

    async def set_rate(self, value):
        self.rates.append(value)
        return FakeResponse()

    async def seek(self, position):
        self.seeks.append(position)
        return FakeResponse()

    async def stop_playback(self):
        self.stop_calls += 1
        return FakeResponse()

    def teardown(self):
        self.did_teardown = True


def decode_command(body):
    outer = plistlib.loads(body)
    assert set(outer) == {"params"}
    assert set(outer["params"]) == {"data"}
    return plistlib.loads(outer["params"]["data"])


class QueueProtocol(HELPER.AirCillerAirPlayV2):
    def __init__(self):
        self.rtsp = FakeRTSP()
        self.context = type("Context", (), {"credentials": None})()
        self.control_stream_id = "7"
        self.current_item_uuid = None
        self.device_id = "24:FC:E5:DE:DB:50"
        self.uuid = "E245392B-8B07-49B1-AB43-D9AB0DFA773D"
        self._verifier = object()
        self._feedback_task = None
        self.event_channel = None
        self._media_ended = asyncio.Event()
        self._terminal_reason = None
        self._did_emit_playing = False
        self._receiver_is_playing = False
        self._control_lock = asyncio.Lock()
        self._metadata_title = ""
        self._metadata_duration = 0.0
        self._metadata_position = 0.0
        self._metadata_artwork = b""
        self._metadata_task = None
        self.setup_calls = 0
        self.feedback_calls = 0

    async def _setup_base(self, timing_server_port):
        self.setup_calls += 1
        self.rtsp.events.append(("AIRPLAY", "PTP_SETUP"))

    async def start_feedback(self):
        self.feedback_calls += 1
        self.rtsp.events.append(("AIRPLAY", "FEEDBACK"))

    def teardown(self):
        pass


async def test_event_confirmation():
    protocol = QueueProtocol()
    output = io.StringIO()
    with redirect_stdout(output):
        protocol.handle_event(
            {
                "type": "playbackState",
                "name": "playing",
                "duration": 100.0,
                "position": 5.0,
            }
        )
        protocol.handle_event({"type": "playbackState", "name": "stopped"})

    text = output.getvalue()
    assert '"event": "playing"' in text
    assert '"duration": 100.0' in text
    assert protocol._media_ended.is_set()
    assert protocol._terminal_reason == "stopped"


async def test_nested_receiver_events_and_cmtime():
    protocol = QueueProtocol()
    protocol._did_emit_playing = True
    output = io.StringIO()
    with redirect_stdout(output):
        protocol.handle_event(
            {
                "type": "playbackStateChanged",
                "item": {"name": "Test Movie"},
                "params": {
                    "playbackState": 2,
                    "elapsedTime": {"value": 1475, "timescale": 10},
                    "duration": {"value": 64270, "timescale": 10},
                },
            }
        )
        protocol.handle_event(
            {
                "type": "playbackStatus",
                "params": {
                    "state": "resumed",
                    "currentTime": {"value": 296, "timescale": 2},
                },
            }
        )

    events = [json.loads(line) for line in output.getvalue().splitlines()]
    assert events[0] == {
        "event": "paused",
        "duration": 6427.0,
        "position": 147.5,
        "playing": False,
        "source": "receiver",
    }
    assert events[1]["event"] == "resumed"
    assert events[1]["playing"] is True
    assert events[1]["position"] == 148.0
    assert events[1]["source"] == "receiver"


async def test_natural_end_is_not_remote_stop():
    protocol = QueueProtocol()
    protocol._did_emit_playing = True
    protocol.handle_event(
        {"type": "notification", "params": {"name": "itemPlayedToEnd"}}
    )
    assert protocol._media_ended.is_set()
    assert protocol._terminal_reason == "ended"


async def test_event_without_timeline_does_not_reset_position():
    protocol = QueueProtocol()
    output = io.StringIO()
    with redirect_stdout(output):
        protocol.handle_event({"type": "playbackState", "name": "playing"})

    event = json.loads(output.getvalue())
    assert event["event"] == "playing"
    assert event["position"] is None
    assert event["duration"] is None


async def test_playback_loop_uses_events_not_playback_info():
    rtsp = FakeRTSP()
    protocol = FakeProtocol()
    reader = asyncio.StreamReader()
    reader.feed_data(
        b'{"command":"pause"}\n'
        b'{"command":"resume"}\n'
        b'{"command":"seek","position":42.5}\n'
        b'{"command":"stop"}\n'
    )

    output = io.StringIO()
    with redirect_stdout(output):
        await HELPER.playback_loop(rtsp, protocol, True, reader)

    assert protocol.rates == [0.0, 1.0]
    assert protocol.seeks == [42.5]
    assert protocol.stop_calls == 1
    assert protocol.did_teardown
    assert ("GET", "/playback-info") not in rtsp.connection.requests
    assert '"event": "stopped"' in output.getvalue()
    assert '"event": "paused", "source": "command"' in output.getvalue()
    assert '"event": "resumed", "source": "command"' in output.getvalue()
    assert '"event": "seeked", "position": 42.5, "source": "command"' in output.getvalue()


async def test_receiver_end_event():
    rtsp = FakeRTSP()
    protocol = FakeProtocol()
    reader = asyncio.StreamReader()

    async def finish():
        await asyncio.sleep(0.01)
        protocol.end_event.set()

    finisher = asyncio.create_task(finish())
    output = io.StringIO()
    with redirect_stdout(output):
        await HELPER.playback_loop(rtsp, protocol, True, reader)
    await finisher

    assert '"event": "ended"' in output.getvalue()
    assert protocol.did_teardown


async def test_pairing_pin_has_timeout():
    config = type("Config", (), {"name": "Apple TV de prueba"})()
    pairing = type(
        "Pairing",
        (),
        {
            "begin": lambda self: asyncio.sleep(0),
            "close": lambda self: asyncio.sleep(0),
        },
    )()
    args = type("Args", (), {"timeout": 5, "address": "198.51.100.33"})()

    async def timeout(awaitable, *_args, **_kwargs):
        awaitable.close()
        raise asyncio.TimeoutError

    with (
        patch.object(HELPER, "discover", return_value=[config]),
        patch.object(
            HELPER,
            "describe_device",
            return_value={"id": "device", "name": "Apple TV de prueba"},
        ),
        patch.object(HELPER.pyatv, "pair", return_value=pairing),
        patch.object(HELPER, "connect_stdin", return_value=asyncio.StreamReader()),
        patch.object(HELPER.asyncio, "wait_for", side_effect=timeout),
    ):
        try:
            await HELPER.pair_command(args)
        except HELPER.exceptions.PairingError as error:
            assert "caducado" in str(error)
        else:
            raise AssertionError("pairing timeout was not reported")


async def test_pairing_is_verified_before_credentials_are_emitted():
    service = type("Service", (), {"port": 7000, "credentials": None})()
    config = type(
        "Config",
        (),
        {
            "name": "Apple TV de prueba",
            "address": "198.51.100.33",
            "get_service": lambda self, _protocol: service,
        },
    )()

    class Pairing:
        has_paired = True

        def __init__(self):
            self.service = type("PairedService", (), {"credentials": "new-secret"})()

        async def begin(self):
            return None

        def pin(self, value):
            assert value == 1234

        async def finish(self):
            return None

        async def close(self):
            return None

    reader = asyncio.StreamReader()
    reader.feed_data(b'{"pin":"1234"}\n')
    reader.feed_eof()
    connection = FakeConnection([])
    verified = []

    async def verify(credentials, candidate_connection):
        verified.append((credentials, candidate_connection))
        return object()

    async def no_delay(_seconds):
        return None

    args = type("Args", (), {"timeout": 5, "address": "198.51.100.33"})()
    with (
        patch.object(HELPER, "discover", return_value=[config]),
        patch.object(HELPER, "describe_device", return_value={"name": "Apple TV de prueba"}),
        patch.object(HELPER.pyatv, "pair", return_value=Pairing()),
        patch.object(HELPER, "connect_stdin", return_value=reader),
        patch.object(HELPER, "http_connect", return_value=connection),
        patch.object(HELPER, "extract_credentials", return_value="parsed-new-secret"),
        patch.object(HELPER, "verify_connection", side_effect=verify),
        patch.object(HELPER.asyncio, "sleep", side_effect=no_delay),
        redirect_stdout(io.StringIO()) as output,
    ):
        result = await HELPER.pair_command(args)

    assert result == 0
    assert service.credentials == "new-secret"
    assert verified == [("parsed-new-secret", connection)]
    assert connection.closed
    events = [json.loads(line) for line in output.getvalue().splitlines()]
    assert events[-1] == {"event": "paired", "credentials": "new-secret"}


async def test_pairing_verification_failure_is_bounded():
    service = type("Service", (), {"port": 7000, "credentials": None})()
    config = type(
        "Config",
        (),
        {
            "name": "Apple TV de prueba",
            "address": "198.51.100.33",
            "get_service": lambda self, _protocol: service,
        },
    )()

    class Pairing:
        has_paired = True

        def __init__(self):
            self.service = type("PairedService", (), {"credentials": "new-secret"})()

        async def begin(self):
            return None

        def pin(self, _value):
            return None

        async def finish(self):
            return None

        async def close(self):
            return None

    reader = asyncio.StreamReader()
    reader.feed_data(b'{"pin":"1234"}\n')
    reader.feed_eof()
    connections = []

    async def connect(*_args, **_kwargs):
        connection = FakeConnection([])
        connections.append(connection)
        return connection

    async def reject(*_args, **_kwargs):
        raise HELPER.exceptions.AuthenticationError("not authenticated")

    async def no_delay(_seconds):
        return None

    args = type("Args", (), {"timeout": 5, "address": "198.51.100.33"})()
    with (
        patch.object(HELPER, "discover", return_value=[config]),
        patch.object(HELPER, "describe_device", return_value={"name": "Apple TV de prueba"}),
        patch.object(HELPER.pyatv, "pair", return_value=Pairing()),
        patch.object(HELPER, "connect_stdin", return_value=reader),
        patch.object(HELPER, "http_connect", side_effect=connect),
        patch.object(HELPER, "extract_credentials", return_value="parsed-new-secret"),
        patch.object(HELPER, "verify_connection", side_effect=reject),
        patch.object(HELPER.asyncio, "sleep", side_effect=no_delay),
        redirect_stdout(io.StringIO()) as output,
    ):
        try:
            await HELPER.pair_command(args)
        except HELPER.exceptions.AuthenticationError as error:
            assert "credencial nueva" in str(error)
        else:
            raise AssertionError("an unverified pairing was accepted")

    assert len(connections) == 3
    assert all(connection.closed for connection in connections)
    assert '"event": "paired"' not in output.getvalue()


async def test_authorization_preflight_uses_stdin_credential():
    service = type("Service", (), {"port": 7000, "credentials": None})()
    config = type(
        "Config",
        (),
        {
            "address": "198.51.100.33",
            "get_service": lambda self, _protocol: service,
        },
    )()
    reader = asyncio.StreamReader()
    reader.feed_data(b'{"credentials":"saved-secret"}\n')
    reader.feed_eof()
    connection = FakeConnection([])
    verified = []

    async def connect(*_args, **_kwargs):
        return connection

    async def verify(credentials, candidate_connection):
        verified.append((credentials, candidate_connection))
        return object()

    args = type("Args", (), {"timeout": 5, "address": "198.51.100.33"})()
    with (
        patch.object(HELPER, "discover", return_value=[config]),
        patch.object(HELPER, "describe_device", return_value={"name": "Apple TV de prueba"}),
        patch.object(HELPER, "connect_stdin", return_value=reader),
        patch.object(HELPER, "http_connect", side_effect=connect),
        patch.object(HELPER, "extract_credentials", return_value="parsed-secret"),
        patch.object(HELPER, "verify_connection", side_effect=verify),
        redirect_stdout(io.StringIO()) as output,
    ):
        result = await HELPER.authorize_command(args)

    assert result == 0
    assert service.credentials == "saved-secret"
    assert verified == [("parsed-secret", connection)]
    assert connection.closed
    assert '"event": "authorized"' in output.getvalue()


async def test_authorization_preflight_allows_transient_hap():
    service = type("Service", (), {"port": 7000, "credentials": None})()
    config = type(
        "Config",
        (),
        {
            "address": "198.51.100.33",
            "get_service": lambda self, _protocol: service,
        },
    )()
    reader = asyncio.StreamReader()
    reader.feed_data(b'{"credentials":""}\n')
    reader.feed_eof()
    connection = FakeConnection([])
    verified = []

    async def verify(credentials, candidate_connection):
        verified.append((credentials, candidate_connection))
        return object()

    args = type("Args", (), {"timeout": 5, "address": "198.51.100.33"})()
    with (
        patch.object(HELPER, "discover", return_value=[config]),
        patch.object(HELPER, "describe_device", return_value={"name": "Apple TV de prueba"}),
        patch.object(HELPER, "connect_stdin", return_value=reader),
        patch.object(HELPER, "http_connect", return_value=connection),
        patch.object(HELPER, "extract_credentials", return_value="transient"),
        patch.object(HELPER, "verify_connection", side_effect=verify),
        redirect_stdout(io.StringIO()) as output,
    ):
        result = await HELPER.authorize_command(args)

    assert result == 0
    assert service.credentials is None
    assert verified == [("transient", connection)]
    assert connection.closed
    assert '"event": "authorized"' in output.getvalue()


async def test_airplay2_queue_commands():
    protocol = QueueProtocol()
    response = await protocol.play_url(
        12345,
        "http://mac.local/movie/master.m3u8",
        12.5,
        6427.25,
        "Test Movie",
        b"\x89PNG\r\n\x1a\nAirCiller",
    )

    assert response.code == 200
    assert protocol.setup_calls == 1
    assert protocol.feedback_calls == 1
    assert protocol.rtsp.events == [
        ("AIRPLAY", "PTP_SETUP"),
        ("RTSP", "RECORD"),
        ("POST", "/command"),
        ("POST", "/command"),
        ("POST", "/command"),
        ("AIRPLAY", "FEEDBACK"),
    ]
    assert len(protocol.rtsp.connection.detailed_requests) == 3

    insert_request, property_request, rate_request = (
        protocol.rtsp.connection.detailed_requests
    )
    assert insert_request["path"] == "/command"
    assert insert_request["headers"]["X-Apple-StreamID"] == "7"
    assert insert_request["headers"]["User-Agent"] == "AirPlay/960.13.1"
    assert "X-Apple-HKP" not in insert_request["headers"]
    assert "X-Apple-Stream-ID" not in insert_request["headers"]

    insert = decode_command(insert_request["body"])
    assert insert["type"] == "insertPlayQueueItem"
    assert insert["item"]["Content-Location"].endswith("master.m3u8")
    assert insert["item"]["Start-Position"] == {
        "epoch": 0,
        "flags": 1,
        "timescale": 1,
        "value": 12,
    }
    assert insert["item"]["uuid"] == protocol.current_item_uuid
    assert insert["item"]["referenceRestrictions"] == 2
    assert insert["item"]["title"] == "Test Movie"
    assert insert["item"]["duration"] == 6427.25
    assert len(insert["item"]["playerLoggingID"]) <= 6

    interested = decode_command(property_request["body"])
    assert interested["type"] == "setProperty"
    assert interested["property"] == "isInterestedInDateRange"
    assert interested["item"] == {"uuid": protocol.current_item_uuid}

    rate = decode_command(rate_request["body"])
    assert rate == {"type": "setRate", "rate": 1}

    # Metadata is deliberately deferred until tvOS has confirmed playback.
    protocol.handle_event(
        {
            "type": "playbackState",
            "name": "playing",
            "duration": 6427.25,
            "position": 12.5,
        }
    )
    assert protocol._metadata_task is not None
    await protocol._metadata_task
    assert len(protocol.rtsp.connection.detailed_requests) == 4
    metadata_request = protocol.rtsp.connection.detailed_requests[-1]

    metadata = decode_command(metadata_request["body"])
    assert metadata["type"] == "updateMRNowPlayingInfo"
    assert metadata["params"]["type"] == "npi-text"
    assert metadata["params"]["mergePolicy"] == "replace"
    now_playing = metadata["params"]["params"]
    assert now_playing["kMRMediaRemoteNowPlayingInfoTitle"] == "Test Movie"
    assert now_playing["kMRMediaRemoteNowPlayingInfoAlbum"] == "AirCiller"
    assert now_playing["kMRMediaRemoteNowPlayingInfoDuration"] == 6427.25
    assert now_playing["kMRMediaRemoteNowPlayingInfoElapsedTime"] == 12.5
    assert now_playing["kMRMediaRemoteNowPlayingInfoMediaType"] == (
        "kMRMediaRemoteNowPlayingInfoTypeVideo"
    )
    assert now_playing["kMRMediaRemoteNowPlayingInfoArtworkMIMEType"] == "image/png"
    assert now_playing["kMRMediaRemoteNowPlayingInfoArtworkData"].startswith(b"\x89PNG")

    await protocol.seek(42.5)
    seek = decode_command(protocol.rtsp.connection.detailed_requests[-1]["body"])
    assert seek["type"] == "seek"
    assert seek["kind"] == "request"
    assert seek["item"] == {"uuid": protocol.current_item_uuid}
    assert seek["time"]["value"] == 42


async def test_airplay2_control_stream_setup():
    protocol = QueueProtocol()
    protocol.control_stream_id = None

    with redirect_stdout(io.StringIO()) as output:
        stream_id = await protocol.ensure_control_stream()

    assert stream_id == "73"
    assert protocol.rtsp.events[:1] == [("RTSP", "SETUP")]
    setup = protocol.rtsp.detailed_requests[-1]
    assert setup["method"] == "SETUP"
    assert setup["headers"] == {}
    stream = setup["body"]["streams"][0]
    assert str(UUID(stream["channelID"])).upper() == stream["channelID"]
    assert stream["clientTypeUUID"] == "A6B27562-B43A-4F2D-B75F-82391E250194"
    assert stream["controlType"] == 1
    assert stream["type"] == 130
    assert "Stream de control AirPlay 2 creado" in output.getvalue()
    assert ("GET", "/playback-info") not in protocol.rtsp.connection.requests


def test_error_classification():
    authentication = HELPER.exceptions.AuthenticationError("HTTP 470")
    playback = HELPER.exceptions.PlaybackError("HTTP 500")
    timeout = asyncio.TimeoutError()
    session_rejected = HELPER.AirPlaySessionRejectedError("SETUP PTP")

    assert HELPER.error_reason(authentication) == "authorizationRequired"
    assert HELPER.error_reason(playback) == "playbackRejected"
    assert HELPER.error_reason(timeout) == "timeout"
    assert HELPER.error_reason(session_rejected) == "playbackRejected"
    assert "autenticación" in HELPER.plain_error(authentication)


async def main():
    await test_event_confirmation()
    await test_nested_receiver_events_and_cmtime()
    await test_natural_end_is_not_remote_stop()
    await test_event_without_timeline_does_not_reset_position()
    await test_playback_loop_uses_events_not_playback_info()
    await test_receiver_end_event()
    await test_pairing_pin_has_timeout()
    await test_pairing_is_verified_before_credentials_are_emitted()
    await test_pairing_verification_failure_is_bounded()
    await test_authorization_preflight_uses_stdin_credential()
    await test_authorization_preflight_allows_transient_hap()
    await test_airplay2_queue_commands()
    await test_airplay2_control_stream_setup()
    test_error_classification()
    print("PTP, eventos, cola y controles AirPlay 2: OK")


if __name__ == "__main__":
    asyncio.run(main())
