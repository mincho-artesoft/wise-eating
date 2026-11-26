#!/usr/bin/env python3
"""Writes <language>.json from work/<language>/out-N.json (and fixes-N.json).

  assemble.py            every language folder under work/
  assemble.py de ja      only these
"""
import pathlib
import sys

here = pathlib.Path(__file__).parent
sys.path.insert(0, str(here.parent))
import translation_batches as tb

tb.assemble(here, "strings.en.json")
