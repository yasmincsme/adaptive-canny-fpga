#!/usr/bin/env python3
"""
Teste em lote de detecção de bordas (iverilog)
================================================
Roda o pipeline completo do Canny APS (canny_top_module + tb_canny_top_module)
para cada imagem encontrada em images/, usando iverilog/vvp.

Para cada imagem:
  1. Converte para build/entrada_canny.hex + build/image_params.vh (scripts/png_to_hex.py)
  2. Compila com iverilog (filelist_canny_top.f -- lista dedicada a este
     teste, independente do filelist.f principal usado por outros testes)
  3. Roda a simulação (vvp)
  4. Reconstrói o resultado em PNG (scripts/hex_to_png.py), salvo em
     images/results/<nome>_edges.png

Atenção: este simulador processa ~1 pixel a cada ~52 ciclos. Uma imagem
512x512 (padrão) leva ~26min para simular. Use --width/--height menores
para iterar mais rápido.

Uso:
  python3 scripts/run_batch_edge_tests.py                          # 512x512, ~26min/imagem
  python3 scripts/run_batch_edge_tests.py --width 128 --height 128 # ~2min/imagem
"""

import argparse
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
BUILD_DIR = REPO_ROOT / "build"
FILELIST = REPO_ROOT / "filelist_canny_top.f"
SIM_BIN = BUILD_DIR / "sim_canny_top.vvp"

IMG_EXTS = (".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".pgm")


def read_filelist():
    files = []
    for line in FILELIST.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        files.append(line)
    return files


def compile_design():
    cmd = ["iverilog", "-g2012", "-I", "build", "-o", str(SIM_BIN)] + read_filelist()
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print("ERRO na compilacao (iverilog):", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)


def run_one_image(img_path, width, height, timeout, results_dir):
    name = img_path.stem
    print(f"\n=== {img_path.name} ===")

    # 1. Converte a imagem
    cmd = [sys.executable, str(REPO_ROOT / "scripts" / "png_to_hex.py"), str(img_path)]
    if width is not None:
        cmd += ["--width", str(width), "--height", str(height)]
    conv = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if conv.returncode != 0:
        print(f"  ERRO ao converter {img_path.name}:\n{conv.stderr}", file=sys.stderr)
        return None
    print(f"  {conv.stdout.strip().splitlines()[0]}")

    # 2. Compila (IMG_WIDTH/IMG_HEIGHT sao fixados em tempo de compilacao via
    # `include "image_params.vh"`, que acabou de ser reescrito acima -- por
    # isso a compilacao precisa acontecer a cada imagem, nao uma unica vez.)
    print("  Compilando...")
    compile_design()

    # 3. Roda a simulacao
    t0 = time.time()
    try:
        sim = subprocess.run(["vvp", str(SIM_BIN)], cwd=REPO_ROOT,
                              capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"  ERRO: simulacao excedeu {timeout}s para {img_path.name}", file=sys.stderr)
        return None
    elapsed = time.time() - t0

    if "Simulacao Concluida com Sucesso!" not in sim.stdout:
        print(f"  ERRO: simulacao nao terminou corretamente para {img_path.name}", file=sys.stderr)
        print(sim.stdout[-2000:], file=sys.stderr)
        return None

    valid_count = None
    for line in sim.stdout.splitlines():
        if "Pixeis validos exportados" in line:
            valid_count = line.split(":")[-1].strip()

    # 4. Reconstroi a saida em PNG
    out_png = results_dir / f"{name}_edges.png"
    rec = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "hex_to_png.py"), "--out", str(out_png)],
        cwd=REPO_ROOT, capture_output=True, text=True
    )
    if rec.returncode != 0:
        print(f"  ERRO ao reconstruir PNG de {img_path.name}:\n{rec.stderr}", file=sys.stderr)
        return None

    print(f"  OK ({elapsed:.1f}s, {valid_count} pixeis validos) -> {out_png.relative_to(REPO_ROOT)}")
    return {"image": img_path.name, "elapsed": elapsed, "valid_count": valid_count, "out": out_png}


def main():
    parser = argparse.ArgumentParser(
        description="Roda o teste de deteccao de bordas para todas as imagens em images/"
    )
    parser.add_argument("--images_dir", type=str, default=str(REPO_ROOT / "images"),
                         help="Diretorio com as imagens de teste (padrao: images/)")
    parser.add_argument("--results_dir", type=str, default=None,
                         help="Diretorio de saida dos PNGs de borda (padrao: <images_dir>/results)")
    parser.add_argument("--width", type=int, default=None,
                         help="Redimensiona todas as imagens para esta largura (padrao: 512, ver png_to_hex.py)")
    parser.add_argument("--height", type=int, default=None,
                         help="Redimensiona todas as imagens para esta altura (padrao: 512, ver png_to_hex.py)")
    parser.add_argument("--timeout", type=int, default=1800,
                         help="Timeout por imagem em segundos (padrao: 1800 -- "
                              "512x512 leva ~26min por imagem neste simulador)")
    args = parser.parse_args()

    if (args.width is None) != (args.height is None):
        print("ERRO: --width e --height devem ser fornecidos juntos", file=sys.stderr)
        sys.exit(1)

    images_dir = Path(args.images_dir)
    results_dir = Path(args.results_dir) if args.results_dir else images_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    images = sorted(p for p in images_dir.iterdir() if p.suffix.lower() in IMG_EXTS)
    if not images:
        print(f"Nenhuma imagem encontrada em {images_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Encontradas {len(images)} imagens em {images_dir}.")

    results = []
    for img_path in images:
        res = run_one_image(img_path, args.width, args.height, args.timeout, results_dir)
        if res:
            results.append(res)

    print("\n=== RESUMO ===")
    for r in results:
        print(f"  {r['image']:20s} {r['elapsed']:6.1f}s  {r['valid_count']:>10s} px  -> {r['out'].name}")
    print(f"\n{len(results)}/{len(images)} imagens processadas com sucesso.")


if __name__ == "__main__":
    main()
