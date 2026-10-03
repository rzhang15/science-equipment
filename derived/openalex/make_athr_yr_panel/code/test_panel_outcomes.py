"""Run the Stata panel builder on small papers with known author positions.

Run with: python test_panel_outcomes.py
Requires the project's pandas installation, Stata, and Stata ado packages.
All inputs and outputs are isolated in a temporary directory.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import numpy as np
import pandas as pd


class PanelOutcomesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="sci_eq_panel_test_")
        cls.root = root = Path(cls.tmp.name)
        for part in ["code", "temp", "output", "external/openalex",
                     "external/clusters", "external/patents",
                     "external/sub_athrs/last", "external/year_insts"]:
            (root / part).mkdir(parents=True, exist_ok=True)
        papers = [("P1", ["A", "B", "C"], 2012, 12),
                  ("P2", ["A"], 2013, 8),
                  ("P3", ["B", "D", "E"], 2014, 20),
                  ("P4", ["C", "A"], 2015, 6),
                  ("P5", ["A", "B"], 2012, 6)]
        rows = []
        for pmid, authors, year, cites in papers:
            for pos, aid in enumerate(authors, 1):
                rows.append(dict(id=pmid, pmid=pmid, athr_id=aid,
                                 which_athr=pos, which_affl=1,
                                 pub_date=pd.Timestamp(f"{year}-06-01"),
                                 year=year, jrnl="Journal", cite_count=cites,
                                 athr_name=aid, country_code="US", msa_comb="MSA",
                                 msa_c_world="MSA", inst="University",
                                 inst_id="I1", msacode="1"))
        df = pd.DataFrame(rows)
        df.to_stata(root / "external/openalex/cleaned_toy.dta", write_index=False)
        last = df.sort_values("which_athr").groupby("pmid").tail(1).copy()
        last["which_athr"] = 1  # Simulate the renumbered upstream last-only file.
        last.to_stata(root / "external/sub_athrs/last/cleaned_toy.dta", write_index=False)
        # E is the original last author of P3, but has no cluster assignment.
        pd.DataFrame({"athr_id": ["A", "B", "C", "D"],
                      "cluster_label": [1, 1, 2, 2]}).to_csv(
                          root / "external/clusters/author_static_clusters_30.csv", index=False)
        pd.DataFrame({"id": [p[0] for p in papers], "patent_count": 1.,
                      "front_only": 1., "body_only": 1.}).to_stata(
                          root / "external/patents/patent_ppr_cnt.dta", write_index=False)
        inst = df[["athr_id", "year", "inst", "inst_id", "msa_comb",
                   "msa_c_world", "msacode", "country_code"]].drop_duplicates(["athr_id", "year"])
        inst.to_stata(root / "external/year_insts/filled_in_panel_all_year.dta", write_index=False)
        source = Path(__file__).with_name("build.do").read_text()
        source = re.sub(r"program main\n.*?\nend", "", source, count=1, flags=re.S)
        source = source.rsplit("\nmain", 1)[0]
        source += "\nmake_panel, time(year) samp(toy) us(1)\n"
        source += "make_panel, time(year) samp(toy) us(1) last(1) metadata(1)\n"
        source += "make_panel, time(year) samp(toy) us(1) last(1) nosolo(1) metadata(1)\n"
        (root / "code/test.do").write_text(source)
        stata = shutil.which("stata-mp") or shutil.which("stata")
        if not stata:
            raise RuntimeError("Stata is required for these integration tests")
        env = dict(os.environ, STATATMP=str(root / "temp"))
        subprocess.run([stata, "-b", "do", "test.do"], cwd=root / "code",
                       env=env, check=True, timeout=180)
        log = (root / "code/test.log").read_text()
        if re.search(r"^r\(\d+\);", log, re.M):
            raise AssertionError(log[-4000:])
        cls.any = pd.read_stata(root / "output/athr_panel_full_year_toy.dta").set_index(["athr_id", "year"])
        cls.last = pd.read_stata(root / "output/athr_panel_full_year_last_toy.dta").set_index(["athr_id", "year"])
        cls.nosolo = pd.read_stata(root / "output/athr_panel_full_year_last_no_solo_toy.dta").set_index(["athr_id", "year"])

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_original_positions_survive_selection(self):
        self.assertEqual(self.any.loc[("D", 2014), "n_last_ppr"], 0)
        self.assertEqual(self.any.loc[("D", 2014), "n_middle_ppr"], 1)
        self.assertAlmostEqual(self.any.loc[("D", 2014), "avg_position_rat"], 2 / 3)
        self.assertEqual(self.last.loc[("C", 2012), "avg_position"], 3)
        self.assertEqual(self.last.loc[("C", 2012), "n_solo_ppr"], 0)
        self.assertEqual(self.last.loc[("A", 2013), "n_solo_ppr"], 1)
        self.assertNotIn(("A", 2013), self.nosolo.index)
        self.assertTrue(self.nosolo.n_solo_ppr.eq(0).all())

    def test_counts_partition_without_changing_headline_counts(self):
        expected = {("A", 2012): 2, ("A", 2013): 1, ("A", 2015): 1,
                    ("B", 2012): 2, ("B", 2014): 1, ("C", 2012): 1,
                    ("C", 2015): 1, ("D", 2014): 1}
        self.assertEqual(self.any.ppr_cnt.to_dict(), expected)
        self.assertEqual(self.last.ppr_cnt.to_dict(),
                         {("A", 2013): 1, ("A", 2015): 1,
                          ("B", 2012): 1, ("C", 2012): 1})
        np.testing.assert_array_equal(self.any.n_first_ppr + self.any.n_middle_ppr + self.any.n_last_ppr,
                                      self.any.ppr_cnt)
        np.testing.assert_array_equal(self.any.ppr_cnt_notlast + self.any.n_last_ppr, self.any.ppr_cnt)

    def test_nonlast_weights_are_direct_paper_sums(self):
        # B has a middle-author P1 and last-author P5 in the same year.
        self.assertAlmostEqual(self.any.loc[("B", 2012), "affl_wt_notlast"], 1 / 3)
        self.assertAlmostEqual(self.any.loc[("D", 2014), "affl_wt_notlast"], 1 / 3)
        self.assertGreater(self.any.loc[("B", 2012), "cite_affl_wt_notlast"], 0)
        self.assertTrue(self.last.cite_affl_wt_notlast.eq(0).all())
        # P1's first and middle authors receive the same common citation weight.
        self.assertAlmostEqual(self.any.loc[("A", 2012), "cite_affl_wt_notlast"],
                               self.any.loc[("B", 2012), "cite_affl_wt_notlast"] +
                               self.any.loc[("B", 2012), "cite_affl_wt_last_common"])


if __name__ == "__main__":
    unittest.main()
