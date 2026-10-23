"""Offline coverage of zeroconf through AirCiller's actual pyatv discovery path."""

import importlib.metadata
import importlib.util
from ipaddress import IPv4Address
from pathlib import Path
import struct
import unittest
from unittest.mock import AsyncMock, Mock, patch

from pyatv.const import Protocol
from pyatv.core import mdns
from pyatv.support.dns import DnsMessage, DnsResource, QueryType, format_txt_dict, qname_encode
from zeroconf.asyncio import AsyncServiceInfo


PROJECT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "airciller_zeroconf_helper", PROJECT / "Scripts/airplay_helper.py"
)
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)
ADDRESS = "192.0.2.20"
SERVICE = "_airplay._tcp.local"
INSTANCE = "AirCiller Test." + SERVICE
HOST = "airciller-test.local"
PROPERTIES = {
    "deviceid": "02:00:00:00:00:20",
    "model": "AppleTV14,1",
    "osvers": "27.0",
    "features": "0x00000000,0x00020040",  # Video V2 and UnifiedMediaControl; synthetic.
    "pw": "false",
}


def response(port=7000):
    """Round-trip synthetic DNS bytes, including zeroconf's TXT encoder."""
    message = DnsMessage(flags=0x8400)
    for name, kind, data in (
        (SERVICE, QueryType.PTR, qname_encode(INSTANCE)),
        (INSTANCE, QueryType.SRV, struct.pack(">HHH", 0, 0, port) + qname_encode(HOST)),
        (INSTANCE, QueryType.TXT, format_txt_dict(PROPERTIES)),
        (HOST, QueryType.A, IPv4Address(ADDRESS).packed),
    ):
        message.resources.append(DnsResource(name, kind, 1, 120, len(data), data))
    decoded = DnsMessage().unpack(message.pack())
    return mdns.Response(mdns.ServiceParser().add_message(decoded).parse(), False, None)


class ZeroconfCompatibilityTests(unittest.IsolatedAsyncioTestCase):
    def test_installed_version_matches_input_and_lock(self):
        version = importlib.metadata.version("zeroconf")
        for filename in ("requirements.in", "requirements.lock"):
            pins = [line.split()[0] for line in (PROJECT / filename).read_text().splitlines()
                    if line.startswith("zeroconf==")]
            self.assertEqual(pins, [f"zeroconf=={version}"])

    def test_txt_empty_and_valueless_entries_remain_distinct(self):
        encoded = format_txt_dict({"empty": b"", "flag": None, "name": "Prüfung"})
        expected = [b"empty=", b"flag", "name=Prüfung".encode()]
        self.assertEqual(encoded, b"".join(bytes([len(value)]) + value for value in expected))

    def test_async_service_info_retains_pyatv_address_interface(self):
        info = AsyncServiceInfo(SERVICE + ".", INSTANCE + ".",
                                addresses=[IPv4Address(ADDRESS).packed],
                                port=7000, properties=PROPERTIES)
        self.assertEqual(info.parsed_addresses(), [ADDRESS])
        self.assertEqual(info.properties[b"deviceid"], PROPERTIES["deviceid"].encode())

    def assert_device(self, devices):
        self.assertEqual(len(devices), 1)
        self.assertIsNotNone(devices[0].get_service(Protocol.AirPlay))
        description = HELPER.describe_device(devices[0])
        for key, expected in {"id": PROPERTIES["deviceid"], "name": "AirCiller Test",
                              "address": ADDRESS, "port": 7000, "model": "AppleTV14,1",
                              "osVersion": "27.0", "protocolVersion": "AirPlay 2",
                              "requiresPassword": False}.items():
            self.assertEqual(description[key], expected, key)

    async def test_multicast_discovery_uses_real_parser_and_service_mapping(self):
        # Only the network edge is replaced: discover, pyatv.scan, service parsing,
        # configuration and describe_device are the production implementations.
        with patch("pyatv.core.scan.mdns.multicast", new_callable=AsyncMock,
                   return_value=[response()]) as multicast:
            self.assert_device(await HELPER.discover(timeout=1))
        multicast.assert_awaited_once()
        self.assertIn(SERVICE, multicast.call_args.args[1])

    async def test_unicast_discovery_cancels_knocker_and_preserves_metadata(self):
        knocker = Mock()
        with patch("pyatv.core.scan.knock.knocker", new_callable=AsyncMock,
                   return_value=knocker), patch("pyatv.core.scan.mdns.unicast",
                   new_callable=AsyncMock, return_value=response()) as unicast:
            self.assert_device(await HELPER.discover(timeout=1, address=ADDRESS))
        unicast.assert_awaited_once()
        self.assertEqual(unicast.call_args.args[1], ADDRESS)
        knocker.cancel.assert_called_once_with()

    async def test_unusable_service_is_not_reported_as_device(self):
        with patch("pyatv.core.scan.mdns.multicast", new_callable=AsyncMock,
                   return_value=[response(port=0)]):
            self.assertEqual(await HELPER.discover(timeout=1), [])


if __name__ == "__main__":
    unittest.main()
