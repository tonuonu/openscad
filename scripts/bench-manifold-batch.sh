#!/usr/bin/env bash
# TEMPORARY benchmarking aid for the perf/manifold-batch-boolean branch (remove before merge).
#
# A/Bs the batched vs sequential Manifold boolean dispatch using a SINGLE build:
#   default            -> batched (Manifold::BatchBoolean)
#   OPENSCAD_MANIFOLD_SEQUENTIAL=1 -> old pairwise fold
#
# Usage:  scripts/bench-manifold-batch.sh /path/to/openscad [reps]
# Reports min-of-reps wall time for each path + speedup, on several stress models, plus platform info.
set -euo pipefail
BIN="${1:?usage: bench-manifold-batch.sh <openscad-binary> [reps]}"
REPS="${2:-5}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/union.scad"        <<'EOF'
$fn=24; n=22; for (x=[0:n-1],y=[0:n-1]) translate([x*4.2,y*4.2,0]) sphere(3);
EOF
cat > "$TMP/difference.scad"   <<'EOF'
$fn=32; n=22;
difference(){ cube([n*5,n*5,8],center=true);
  for (x=[0:n-1],y=[0:n-1]) translate([x*5-(n-1)*2.5,y*5-(n-1)*2.5,0]) cylinder(h=12,r=1.6,center=true); }
EOF
cat > "$TMP/intersection.scad" <<'EOF'
$fn=64; intersection(){ for(i=[0:11]) rotate([0,0,i*15]) translate([4,0,0]) sphere(12); }
EOF

ncpu="$( (nproc 2>/dev/null) || sysctl -n hw.ncpu 2>/dev/null || echo '?')"
echo "platform: $(uname -srm)  cpus=$ncpu  reps=$REPS  binary=$BIN"
echo "(seq/batch runs are INTERLEAVED per rep to cancel thermal drift; reported = min-of-reps)"
printf '%-16s %10s %10s %9s\n' model sequential batched speedup

bench_model() { # model.scad -> prints "seqmin batchmin"
  python3 - "$REPS" "$BIN" --backend Manifold -o "$TMP/o.stl" "$1" <<'PY'
import subprocess,time,sys,os
reps=int(sys.argv[1]); cmd=sys.argv[2:]
def run(seq):
    env=dict(os.environ)
    if seq: env["OPENSCAD_MANIFOLD_SEQUENTIAL"]="1"
    else:   env.pop("OPENSCAD_MANIFOLD_SEQUENTIAL",None)
    t=time.time(); subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=env)
    return time.time()-t
bs=bb=1e9
for _ in range(reps):            # interleave seq/batch each rep so both see the same thermal state
    bs=min(bs,run(True)); bb=min(bb,run(False))
print(f"{bs:.3f} {bb:.3f}")
PY
}

for m in union difference intersection; do
  read s b <<<"$(bench_model "$TMP/$m.scad")"
  sp=$(python3 -c "print(f'{$s/$b:.2f}x')")
  printf '%-16s %10s %10s %9s\n' "$m" "$s" "$b" "$sp"
done
