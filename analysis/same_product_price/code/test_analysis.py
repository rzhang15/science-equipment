"""Focused checks for package parsing and the repeated-product estimand."""
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from analysis import volume, MULTIPACK, MEDIA, analyze


class SameProductTests(unittest.TestCase):
    def test_packages_and_nonserum(self):
        self.assertEqual(volume("FBS USDA APPROVED 1X500ML"), 500)
        self.assertEqual(volume("F2442-500 ML"), 500)
        self.assertEqual(volume("FBS 50ml"), 50)
        self.assertTrue(np.isnan(volume("FBS 500ml or 100ml")))
        for text in ["FBS 6x500ml", "FBS 500ml 12/pack", "FBS 500ml two for one sale"]:
            self.assertIsNotNone(MULTIPACK.search(text))
        self.assertIsNone(MULTIPACK.search("FBS 1X500ML"))
        self.assertIsNotNone(MEDIA.search("pharmingen stain fbs buf 500ml"))
        self.assertIsNotNone(MEDIA.search("DMEM 500ml 10% FBS"))

    def test_observed_year_weights_and_both_period_support(self):
        # Repeated transactions in one year must not overweight that year.
        d = pd.DataFrame({
            "agencyname": ["buyer"] * 5, "supplier_key": ["supplier"] * 5,
            "description_key": ["same"] * 4 + ["pre only"],
            "product_desc": ["FBS 500ml"] * 5, "sku": [""] * 5,
            "embedded_sku": [""] * 5,
            "year": [2010, 2010, 2013, 2016, 2013],
            "price": [10., 30., 20., 40., 500.], "qty": [1.] * 5,
            "spend": [10., 30., 20., 40., 500.],
        })
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            for sub in ["tables", "audit"]:
                (out / sub).mkdir()
            retained, annual, pairs = analyze(d, "synthetic", "description", out)
            self.assertEqual(len(pairs), 1)
            self.assertEqual(len(retained), 4)
            self.assertEqual(set(annual.year), {2010, 2013, 2016})
            expected_pre = (np.log(10) + np.log(30)) / 4 + np.log(20) / 2
            self.assertAlmostEqual(pairs.log_change.iloc[0], np.log(40) - expected_pre)
            self.assertEqual(pairs.spend_pre.iloc[0], 60.)
            self.assertEqual(pairs.years_pre.iloc[0], 2)


if __name__ == "__main__":
    unittest.main()
