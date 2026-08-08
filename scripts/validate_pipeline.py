#!/usr/bin/env python3
"""
Script 1 — Validação Funcional do Pipeline  (Seção IV-B do artigo)
====================================================================
Compara a saída da simulação RTL (iverilog, modo APS) com uma referência
de software (cv2.Canny), gerando a figura de 3 painéis descrita no artigo.
Exibe também a projeção de latência/FPS a partir da contagem de ciclos
impressa pelo testbench (resultado de SIMULAÇÃO, não de hardware real).

Uso:
  python3 scripts/validate_pipeline.py
  python3 scripts/validate_pipeline.py --image images/lena.png --width 256 --height 256
  python3 scripts/validate_pipeline.py --mdp 91  # MDP desejado: 91|92|93|94
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------
REPO_ROOT   = Path(__file__).parent.parent
BUILD_DIR   = REPO_ROOT / "build"
FILELIST    = REPO_ROOT / "filelist_canny_top.f"
SIM_BIN     = BUILD_DIR / "sim_canny_top.vvp"
CONFIG_JSON = REPO_ROOT / "src" / "config_table" / "config_table.json"

# Escala da magnitude de gradiente usada pelo hardware (canny_top_module.v)
GRAD_MAG_FULL_SCALE = 256

# Limiar do estimador de ruído (calibrado no testbench para não confundir
# textura real com ruído — ver comentário no tb_canny_top_module.v)
HW_NOISE_THRESH = 60

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_config_table():
    if CONFIG_JSON.is_file():
        return json.loads(CONFIG_JSON.read_text())
    print(f"[AVISO] {CONFIG_JSON} não encontrado — usando limiares padrão.", file=sys.stderr)
    return None


def get_hw_thresholds(config, noise_pct: int, mdp_pct: int):
    """Retorna (TH_H, TH_L) em domínio de 12 bits para (noise_pct, mdp_pct)."""
    if config:
        entry = config.get(str(mdp_pct), {}).get(str(noise_pct))
        if entry:
            return (round(entry["th_h"] * GRAD_MAG_FULL_SCALE),
                    round(entry["th_l"] * GRAD_MAG_FULL_SCALE))
    # Fallback: Table 4 do artigo, noise=5%, MDP=91%
    return 64, 26


def img_to_gray_avg(img_bgr: np.ndarray) -> np.ndarray:
    """Escala de cinza por média dos 3 canais (igual a rgb_gray_average.v)."""
    return ((img_bgr[:, :, 0].astype(np.uint16)
             + img_bgr[:, :, 1].astype(np.uint16)
             + img_bgr[:, :, 2].astype(np.uint16)) // 3).astype(np.uint8)


def read_filelist():
    return [l.strip() for l in FILELIST.read_text().splitlines()
            if l.strip() and not l.strip().startswith("//")]


def compile_design():
    cmd = ["iverilog", "-g2012", "-I", "build", "-o", str(SIM_BIN)] + read_filelist()
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERRO (iverilog):\n", r.stderr, file=sys.stderr)
        sys.exit(1)


def run_simulation(plusargs: dict, timeout: int = 7200) -> str:
    """Chama vvp com os +args fornecidos. Retorna stdout."""
    cmd = ["vvp", str(SIM_BIN)] + [f"+{k}={v}" for k, v in plusargs.items()]
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout)
    if "Simulacao Concluida com Sucesso!" not in r.stdout:
        print("ERRO (vvp):\n", r.stdout[-2000:], file=sys.stderr)
        sys.exit(1)
    return r.stdout


def convert_to_hex(img_path: Path, width: int, height: int):
    cmd = [sys.executable, str(REPO_ROOT / "scripts" / "png_to_hex.py"),
           str(img_path), "--width", str(width), "--height", str(height)]
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERRO (png_to_hex):\n", r.stderr, file=sys.stderr)
        sys.exit(1)


def convert_from_hex(out_path: Path):
    cmd = [sys.executable, str(REPO_ROOT / "scripts" / "hex_to_png.py"),
           "--out", str(out_path)]
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERRO (hex_to_png):\n", r.stderr, file=sys.stderr)
        sys.exit(1)


def parse_cycle_count(stdout: str):
    for line in stdout.splitlines():
        if "CICLOS_TOTAIS:" in line:
            return int(line.split(":")[-1].strip())
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Validação funcional do pipeline Canny APS (Script 1 do artigo)"
    )
    parser.add_argument("--image",  default="images/lena.png",
                        help="Imagem de entrada (padrão: images/lena.png)")
    parser.add_argument("--width",  type=int, default=256,
                        help="Largura para simulação (padrão: 256)")
    parser.add_argument("--height", type=int, default=256,
                        help="Altura para simulação (padrão: 256)")
    parser.add_argument("--mdp",    type=int, default=94, choices=[91, 92, 93, 94],
                        help="MDP desejado em %% (padrão: 94)")
    parser.add_argument("--out",    default="build/validacao_funcional.png",
                        help="Caminho da figura de saída")
    args = parser.parse_args()

    img_path = REPO_ROOT / args.image
    out_fig  = Path(args.out)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Carregar imagem
    # ------------------------------------------------------------------
    print(f"[1/5] Carregando imagem: {img_path.name} ({args.width}×{args.height})")
    img_bgr = cv2.imread(str(img_path))
    if img_bgr is None:
        print(f"ERRO: imagem não encontrada: {img_path}", file=sys.stderr)
        sys.exit(1)
    img_bgr = cv2.resize(img_bgr, (args.width, args.height),
                         interpolation=cv2.INTER_AREA)
    gray = img_to_gray_avg(img_bgr)

    config = load_config_table()
    th_h_hw, th_l_hw = get_hw_thresholds(config, noise_pct=5, mdp_pct=args.mdp)
    print(f"    Parâmetros APS (ruído 5%, MDP={args.mdp}%): "
          f"TH_H={th_h_hw}, TH_L={th_l_hw} (12 bits)")

    # ------------------------------------------------------------------
    # 2. Referência software (cv2.Canny)
    # ------------------------------------------------------------------
    print("[2/5] Gerando referência OpenCV (σ=1.3, kernel 7×7)...")
    gray_blurred = cv2.GaussianBlur(gray, (7, 7), 1.3)
    # Hardware usa Sobel + mag_approx com escala até ~GRAD_MAG_FULL_SCALE.
    # OpenCV usa Sobel 3×3 + L1 com escala até ~2040 para 8 bits de entrada.
    # Fator de escala empírico: 2040 / 256 ≈ 8.
    cv2_th_h = max(1, round(th_h_hw * 8))
    cv2_th_l = max(1, round(th_l_hw * 8))
    edges_ref = cv2.Canny(gray_blurred, cv2_th_l, cv2_th_h, L2gradient=False)

    # ------------------------------------------------------------------
    # 3. Converter imagem e compilar RTL
    # ------------------------------------------------------------------
    print("[3/5] Convertendo imagem e compilando RTL...")
    convert_to_hex(img_path, args.width, args.height)
    compile_design()

    # ------------------------------------------------------------------
    # 4. Simulação RTL (modo APS)
    # ------------------------------------------------------------------
    mdp_idx = args.mdp - 91          # 91→0, 92→1, 93→2, 94→3
    print(f"[4/5] Simulando (APS ativo, MDP={args.mdp}%, ~{args.width*args.height/1e3:.0f}k px)...")
    stdout = run_simulation({
        "ADAPTIVE_EN": 1,
        "MDP": mdp_idx,
        "NOISE_THRESH": HW_NOISE_THRESH,
    })
    rtl_png = BUILD_DIR / "saida_canny.png"
    convert_from_hex(rtl_png)
    edges_rtl = cv2.imread(str(rtl_png), cv2.IMREAD_GRAYSCALE)
    cycles = parse_cycle_count(stdout)

    # ------------------------------------------------------------------
    # 5. Figura comparativa (3 painéis)
    # ------------------------------------------------------------------
    print("[5/5] Gerando figura comparativa...")

    # A saída RTL perde 5 linhas e 6 colunas (pipeline warm-up + janelas 3×3).
    # Recortamos a referência para alinhar com a saída RTL.
    out_h = args.height - 5
    out_w = args.width  - 6
    # Recorte central: 3 px de cada lado na largura, 2 topo + 3 base na altura
    ref_crop = edges_ref[2: 2 + out_h, 3: 3 + out_w]
    gray_crop = gray[2: 2 + out_h, 3: 3 + out_w]

    fig, axes = plt.subplots(1, 3, figsize=(13, 4.8))
    fig.suptitle(
        f"Validação Funcional do Pipeline Canny APS\n"
        f"Imagem: {img_path.name} — {args.width}×{args.height} px"
        f" — MDP = {args.mdp}%",
        fontsize=11, fontweight="bold"
    )

    axes[0].imshow(gray_crop, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title("(a) Entrada (escala de cinza)", fontsize=10)
    axes[0].axis("off")

    axes[1].imshow(ref_crop, cmap="gray")
    axes[1].set_title(
        f"(b) Referência Software\ncv2.Canny (σ=1.3, T={cv2_th_l}/{cv2_th_h})",
        fontsize=10
    )
    axes[1].axis("off")

    if edges_rtl is not None:
        axes[2].imshow(edges_rtl, cmap="gray")
    axes[2].set_title(
        f"(c) Simulação RTL\nCanny APS (MDP={args.mdp}%)",
        fontsize=10
    )
    axes[2].axis("off")

    plt.tight_layout(rect=[0, 0, 1, 0.93])
    out_fig.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(str(out_fig), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"    Figura salva em: {out_fig}")

    # ------------------------------------------------------------------
    # Relatório de latência
    # ------------------------------------------------------------------
    if cycles:
        n_px = args.width * args.height
        print(f"\n{'='*52}")
        print("  Desempenho Temporal (Simulação RTL)")
        print(f"{'='*52}")
        print(f"  Ciclos totais           : {cycles:>10,}")
        print(f"  Pixels injetados        : {n_px:>10,}  ({args.width}×{args.height})")
        print(f"  Ciclos por pixel        : {cycles/n_px:>10.1f}")
        print(f"  FPS projetado @ 100 MHz : {100e6/cycles:>10.1f}  fps")
        print(f"  FPS projetado @ 150 MHz : {150e6/cycles:>10.1f}  fps")
        print(f"  FPS projetado @ 200 MHz : {200e6/cycles:>10.1f}  fps")
        print("  [NOTA: projeção via simulação + Fmax assumida — não medição em HW]")
        print(f"{'='*52}\n")
    else:
        print("\n[AVISO] Ciclos não encontrados na saída do simulador "
              "(adicione CICLOS_TOTAIS ao testbench).", file=sys.stderr)


if __name__ == "__main__":
    main()
