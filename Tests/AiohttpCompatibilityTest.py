"""Exercise real pyatv/aiohttp session ownership without contacting a receiver."""
import asyncio
from contextlib import redirect_stdout
import importlib.util
from ipaddress import IPv4Address
import io
from pathlib import Path
import socket
import unittest
from unittest.mock import AsyncMock, patch

import aiohttp
import pyatv
from pyatv.conf import AppleTV, ManualService
from pyatv.const import Protocol
from pyatv.protocols.airplay.pairing import AirPlayPairingHandler
from pyatv.support import http
from yarl import URL

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("aiohttp_test_helper", ROOT / "Scripts/airplay_helper.py")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


def configuration():
    result = AppleTV(IPv4Address("127.0.0.1"), "Synthetic receiver")
    result.add_service(ManualService("synthetic-id", Protocol.AirPlay, 7000,
                                    {"features": "0x0,0x10000"}))
    return result


class AiohttpCompatibilityTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.managers = []
        self.errors = []
        self.loop = asyncio.get_running_loop()
        self.previous_handler = self.loop.get_exception_handler()
        self.loop.set_exception_handler(lambda loop, context: self.errors.append(context))
        self.network_guard = patch.object(socket.socket, "connect",
                                          side_effect=AssertionError("Network access is forbidden"))
        self.network_guard.start()
        self.real_create_session = http.create_session

    async def asyncTearDown(self):
        try:
            for manager in self.managers:
                self.assertTrue(manager.session.closed, "An owned aiohttp session leaked")
            await asyncio.sleep(0)
            pending = [task for task in asyncio.all_tasks()
                       if task is not asyncio.current_task() and not task.done()]
            self.assertEqual(pending, [], "Session work survived the operation")
            self.assertEqual(self.errors, [], "Asyncio reported an unhandled failure")
        finally:
            # Preserve failures above while still cleaning resources after a regression.
            for manager in self.managers:
                await manager.session.close()
            self.loop.set_exception_handler(self.previous_handler)
            self.network_guard.stop()

    async def create_session(self, session=None):
        manager = await self.real_create_session(session)
        self.managers.append(manager)
        return manager

    async def test_owned_session_closes_idempotently(self):
        manager = await self.create_session()
        connector = manager.session.connector
        self.assertIsInstance(manager.session, aiohttp.ClientSession)
        self.assertFalse(manager.session.closed)
        await manager.close()
        await manager.close()
        self.assertTrue(connector.closed)

    async def test_yarl_keeps_airplay_http_urls(self):
        for address, host in [("127.0.0.1", "127.0.0.1"), ("[::1]", "::1")]:
            value = f"http://{address}:7000/play?position=1.25"
            url = URL(value)
            self.assertEqual(str(url), value)
            self.assertEqual(url.host, host)
            self.assertEqual(url.port, 7000)
            self.assertEqual(url.query["position"], "1.25")

    async def test_borrowed_session_remains_with_its_owner(self):
        async with aiohttp.ClientSession() as session:
            manager = await self.real_create_session(session)
            await manager.close()
            self.assertIs(manager.session, session)
            self.assertFalse(session.closed)
        self.assertTrue(session.closed)

    async def test_real_airplay_pairing_handler_closes_owned_session(self):
        with patch.object(http, "create_session", side_effect=self.create_session):
            pairing = await pyatv.pair(configuration(), Protocol.AirPlay, self.loop, name="Synthetic")
        self.assertIsInstance(pairing, AirPlayPairingHandler)
        self.assertEqual(len(self.managers), 1)
        await pairing.close()
        await pairing.close()

    async def test_pairing_factory_failure_closes_owned_session(self):
        with patch.object(http, "create_session", side_effect=self.create_session), \
                patch("pyatv.protocols.airplay.AirPlayPairingHandler", side_effect=RuntimeError("factory failed")):
            with self.assertRaisesRegex(RuntimeError, "factory failed"):
                await pyatv.pair(configuration(), Protocol.AirPlay, self.loop)
        self.assertEqual(len(self.managers), 1)

    async def run_helper_failure(self, begin_error=None, request_error=None, request=None):
        args = type("Arguments", (), {"address": "127.0.0.1", "timeout": 1})()
        with patch.object(http, "create_session", side_effect=self.create_session), \
                patch.object(HELPER, "discover", AsyncMock(return_value=[configuration()])), \
                patch.object(AirPlayPairingHandler, "begin", AsyncMock(side_effect=begin_error)), \
                patch.object(HELPER, "connect_stdin", AsyncMock(return_value=object())), \
                patch.object(HELPER, "read_stdin_line", AsyncMock(side_effect=request_error, return_value=request)), \
                redirect_stdout(io.StringIO()):
            await HELPER.pair_command(args)

    async def test_cancelled_pin_wait_closes_real_session(self):
        with self.assertRaises(asyncio.CancelledError):
            await self.run_helper_failure(request_error=asyncio.CancelledError())
        self.assertEqual(len(self.managers), 1)

    async def test_pairing_begin_failure_closes_real_session(self):
        with self.assertRaisesRegex(RuntimeError, "begin failed"):
            await self.run_helper_failure(begin_error=RuntimeError("begin failed"))
        self.assertEqual(len(self.managers), 1)

    async def test_invalid_pin_closes_real_session(self):
        with self.assertRaises(pyatv.exceptions.PairingError):
            await self.run_helper_failure(request={"pin": "invalid"})
        self.assertEqual(len(self.managers), 1)


if __name__ == "__main__":
    unittest.main()
