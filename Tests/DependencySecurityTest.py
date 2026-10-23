"""Offline regressions for the dependency security updates shipped by AirCiller."""

import gc
import hashlib
from pathlib import Path
import ssl
import unittest
import weakref

import certifi
from multidict import CIMultiDict, MultiDict
import requests.certs


class OperandValue:
    pass


class DependencySecurityTests(unittest.TestCase):
    def test_requests_uses_checked_certifi_bundle(self):
        self.assertEqual(Path(requests.certs.where()).resolve(), Path(certifi.where()).resolve())

    def test_compromised_emsign_root_is_not_trusted(self):
        # GHSA-6q48-6c7w-9gw2 identifies this exact root. Its SHA-256 is also
        # published at https://repository.emsign.com/ (ECC Root CA - G3).
        compromised = "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b"
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_verify_locations(cafile=certifi.where())
        roots = context.get_ca_certs(binary_form=True)
        self.assertGreater(len(roots), 100, "The fix must retain a usable CA bundle")
        fingerprints = {hashlib.sha256(root).hexdigest() for root in roots}
        self.assertFalse(compromised in fingerprints, "The compromised emSign root is still trusted")

    def check_operand_release(self, dictionary_type, operation):
        self.assertEqual(dictionary_type.__module__, "multidict._multidict",
                         "Exercise the shipped native extension, not a Python fallback")
        dictionary = dictionary_type([("existing", "value")])
        references = []
        for index in range(20):
            value = OperandValue()
            references.append(weakref.ref(value))
            operand = [(f"operand-{index}", value)]
            if operation == "union":
                result = operand | dictionary.items()
                self.assertEqual(len(result), 2)
            else:
                result = dictionary.items() - operand
                self.assertEqual(result, {("existing", "value")})
            del value, operand, result
        gc.collect()
        self.assertTrue(all(reference() is None for reference in references),
                        "Items-view operation retained its operand values")

    def test_reflected_union_releases_operand_values(self):
        for dictionary_type in (MultiDict, CIMultiDict):
            with self.subTest(dictionary=dictionary_type.__name__):
                self.check_operand_release(dictionary_type, "union")

    def test_subtraction_releases_operand_values(self):
        for dictionary_type in (MultiDict, CIMultiDict):
            with self.subTest(dictionary=dictionary_type.__name__):
                self.check_operand_release(dictionary_type, "subtraction")


if __name__ == "__main__":
    unittest.main()
