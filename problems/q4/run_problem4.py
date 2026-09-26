"""Reproduce the published frozen-Q3 resource-optimal Q4 package."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'q4'))
import final_delivery
import optimality_audit
import make_manifest
import verify_bundle
if __name__=='__main__':
    final_delivery.main()
    optimality_audit.main()
    make_manifest.main()
    verify_bundle.main()
