#!/usr/bin/env python3
"""
Script 2 — Eficácia da Seleção Adaptativa de Parâmetros (Seção IV-C)
======================================================================
Para cada um dos 14 níveis de ruído (5 % a 70 %, passo de 5 %),
roda a simulação RTL em dois modos:
  - FIXO    : ADAPTIVE_EN=0, limiares constantes (calibrados para imagem limpa)
  - ADAPTATIVO: ADAPTIVE_EN=1, limiares selecionados pela tabela APS

Calcula a Figure of Merit de Pratt (FOM) de cada saída em relação a um
gabarito de bordas gerado pelo OpenCV na imagem limpa.

Saídas:
  - build/aps_efficacy.csv   — tabela completa dos resultados
  - build/aps_efficacy.png   — gráfico FOM vs. nível de ruído (duas curvas)

Uso:
  python3 scripts/aps_efficacy.py
  python3 scripts/aps_efficacy.py --image images/lena.png --width 128 --height 128
  python3 scripts/aps_efficacy.py --mdp 94 --alpha 0.111

ATENÇÃO: roda 2 × 14 = 28 simulações.
         Com --width 128 --height 128: ~2 min/simulação → ~56 min no total.
         Com --width 256 --height 256: ~8 min/simulação → ~4 h no total.
"""

import argparse
import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.ndimage import distance_transform_edt

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------
REPO_ROOT   = Path(__file__).parent.parent
BUILD_DIR   = REPO_ROOT / "build"
FILELIST    = REPO_ROOT / "filelist_canny_top.f"
SIM_BIN     = BUILD_DIR / "sim_canny_top.vvp"
CONFIG_JSON = REPO_ROOT / "src" / "config_table" / "config_table.json"

GRAD_MAG_FULL_SCALE = 256
HW_NOISE_THRESH     = 60

# 14 níveis de ruído do APS (% de pixels corrompidos)
NOISE_LEVELS = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70]

# Parâmetros FIXOS: Table 4 do artigo, noise=5%, MDP=91%
# (ótimos para imagem limpa; degradam com ruído crescente)
FIXED_TH_H = 64   # round(0.25 * 256)
FIXED_TH_L = 26   # round(0.10 * 256)

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------

def load_config_table():
    if CONFIG_JSON.is_file():
        return json.loads(CONFIG_JSON.read_text())
    return None


def img_to_gray_avg(img_bgr: np.ndarray) -> np.ndarray:
    """Escala de cinza por média (igual ao hardware rgb_gray_average.v)."""
    return ((img_bgr[:, :, 0].astype(np.uint16)
             + img_bgr[:, :, 1].astype(np.uint16)
             + img_bgr[:, :, 2].astype(np.uint16)) // 3).astype(np.uint8)


def add_salt_pepper(gray: np.ndarray, level_pct: float, rng: np.random.Generator) -> np.ndarray:
    """Adiciona ruído sal-e-pimenta: level_pct % dos pixels são corrompidos."""
    noisy = gray.copy()
    n = round(level_pct / 100 * gray.size)
    coords = rng.choice(gray.size, n, replace=False)
    vals = rng.choice([0, 255], n).astype(np.uint8)
    flat = noisy.flatten()
    flat[coords] = vals
    return flat.reshape(gray.shape)


def pratt_fom(ideal: np.ndarray, detected: np.ndarray, alpha: float = 1/9) -> float:
    """
    Figure of Merit de Pratt:
      FOM = (1 / max(|I|, |R|)) * Σ_i  1 / (1 + α · d²(i))
    onde a soma percorre os pixels de borda detectados e d(i) é a distância
    ao pixel de borda ideal mais próximo.
    """
    ideal_bin    = (ideal    > 0)
    detected_bin = (detected > 0)
    N = max(int(ideal_bin.sum()), int(detected_bin.sum()))
    if N == 0:
        return 1.0
    dist = distance_transform_edt(~ideal_bin)
    ys, xs = np.where(detected_bin)
    fom = float(np.sum(1.0 / (1.0 + alpha * dist[ys, xs] ** 2)))
    return fom / N


def read_filelist():
    return [l.strip() for l in FILELIST.read_text().splitlines()
            if l.strip() and not l.strip().startswith("//")]


def compile_design():
    cmd = ["iverilog", "-g2012", "-I", "build", "-o", str(SIM_BIN)] + read_filelist()
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERRO (iverilog):\n", r.stderr, file=sys.stderr)
        sys.exit(1)


def convert_to_hex(img_path: Path, width: int, height: int):
    cmd = [sys.executable, str(REPO_ROOT / "scripts" / "png_to_hex.py"),
           str(img_path), "--width", str(width), "--height", str(height)]
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERRO (png_to_hex):\n", r.stderr, file=sys.stderr)
        sys.exit(1)


def run_simulation(plusargs: dict, timeout: int = 7200) -> bool:
    """Chama vvp com os +args. Retorna True se bem-sucedido."""
    cmd = ["vvp", str(SIM_BIN)] + [f"+{k}={v}" for k, v in plusargs.items()]
    r = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout)
    return "Simulacao Concluida com Sucesso!" in r.stdout


def read_output_edges(width: int, height: int) -> np.ndarray:
    """Lê build/saida_canny.hex e devolve o mapa de bordas como ndarray."""
    hex_path = BUILD_DIR / "saida_canny.hex"
    out_w, out_h = width - 6, height - 5
    vals = np.array([int(l.strip(), 16)
                     for l in hex_path.read_text().splitlines() if l.strip()],
                    dtype=np.uint8)
    expected = out_w * out_h
    buf = np.zeros(expected, dtype=np.uint8)
    buf[:min(len(vals), expected)] = vals[:expected]
    return buf.reshape(out_h, out_w)


def crop_to_output(img: np.ndarray, width: int, height: int) -> np.ndarray:
    """
    Recorta img (height × width) para a região correspondente à saída RTL
    (height-5) × (width-6), alinhada com o pipeline:
      - 2 linhas do topo e 3 da base são descartadas (warm-up de 7×7 + flush)
      - 3 colunas de cada lado (3 janelas 3×3 em cascata)
    """
    return img[2: height - 3, 3: width - 3]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Curva de eficácia do APS vs. parâmetros fixos (Script 2 do artigo)"
    )
    parser.add_argument("--image",  default="images/lena.png")
    parser.add_argument("--width",  type=int, default=128)
    parser.add_argument("--height", type=int, default=128)
    parser.add_argument("--mdp",    type=int, default=94, choices=[91, 92, 93, 94])
    parser.add_argument("--alpha",  type=float, default=1/9,
                        help="Parâmetro α da FOM de Pratt (padrão: 1/9 ≈ 0.111)")
    parser.add_argument("--seed",   type=int, default=42)
    parser.add_argument("--csv_out", default="build/aps_efficacy.csv")
    parser.add_argument("--fig_out", default="build/aps_efficacy.png")
    args = parser.parse_args()

    img_path = REPO_ROOT / args.image
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(args.seed)
    config = load_config_table()
    mdp_idx = args.mdp - 91   # 91→0, 92→1, 93→2, 94→3

    # ------------------------------------------------------------------
    # 1. Carregar imagem limpa e gerar gabarito de bordas
    # ------------------------------------------------------------------
    print(f"[INIT] Carregando imagem: {img_path.name} ({args.width}×{args.height})")
    img_bgr = cv2.imread(str(img_path))
    if img_bgr is None:
        print(f"ERRO: imagem não encontrada: {img_path}", file=sys.stderr)
        sys.exit(1)
    img_bgr = cv2.resize(img_bgr, (args.width, args.height), interpolation=cv2.INTER_AREA)
    gray_clean = img_to_gray_avg(img_bgr)

    # Gabarito = OpenCV Canny na imagem LIMPA com limiares altos para garantir
    # um mapa esparso (~3-5 %) que represente apenas bordas estruturais relevantes.
    # Usamos th_h=300 no domínio L1 do Sobel OpenCV (máx ~2040 para 8 bits),
    # calibrado empiricamente para dar ~3.5 % de pixels de borda em 128×128.
    gt_th_h, gt_th_l = 300, 120
    gt_blurred = cv2.GaussianBlur(gray_clean, (7, 7), 1.3)
    ground_truth_full = cv2.Canny(gt_blurred, gt_th_l, gt_th_h, L2gradient=False)
    ground_truth = crop_to_output(ground_truth_full, args.width, args.height)
    n_gt = int((ground_truth > 0).sum())
    print(f"[INIT] Gabarito de bordas: {n_gt} pixels ({n_gt/(ground_truth.size)*100:.1f}%)")

    # ------------------------------------------------------------------
    # 2. Compilação inicial (será recompilado a cada imagem pois
    #    image_params.vh muda — ver run_batch_edge_tests.py)
    # ------------------------------------------------------------------
    results = []

    for noise_pct in NOISE_LEVELS:
        print(f"\n--- Nível de ruído: {noise_pct:>2d}% ---")

        # Gerar imagem com ruído sal-e-pimenta
        noisy = add_salt_pepper(gray_clean, noise_pct, rng)

        # Salvar como PNG temporário (mantido em build/ para inspeção)
        tmp_png = BUILD_DIR / f"noisy_{noise_pct:02d}pct.png"
        cv2.imwrite(str(tmp_png), noisy)

        # Converter para hex e recompilar (image_params.vh depende do tamanho)
        convert_to_hex(tmp_png, args.width, args.height)
        compile_design()

        # ---- Modo FIXO -----------------------------------------------
        print(f"  [FIXO]   TH_H={FIXED_TH_H}, TH_L={FIXED_TH_L}...")
        ok_fixo = run_simulation({
            "ADAPTIVE_EN": 0,
            "HIGH_THRESH": FIXED_TH_H,
            "LOW_THRESH":  FIXED_TH_L,
        })
        fom_fixo = 0.0
        if ok_fixo:
            edges_fixo = read_output_edges(args.width, args.height)
            fom_fixo = pratt_fom(ground_truth, edges_fixo, alpha=args.alpha)
            print(f"         FOM = {fom_fixo:.4f}")
        else:
            print("         FALHA na simulação — FOM=0", file=sys.stderr)

        # ---- Modo ADAPTATIVO -----------------------------------------
        # Consultar parâmetros esperados para log (a LUT seleciona dentro do HW)
        if config:
            entry = config.get(str(args.mdp), {}).get(str(noise_pct), {})
            sigma_aps = entry.get("sigma", "?")
            th_h_aps  = entry.get("th_h", "?")
        else:
            sigma_aps, th_h_aps = "?", "?"

        print(f"  [APS]    MDP={args.mdp}%, σ={sigma_aps}, TH_H≈{th_h_aps}...")
        ok_aps = run_simulation({
            "ADAPTIVE_EN": 1,
            "MDP":         mdp_idx,
            "NOISE_THRESH": HW_NOISE_THRESH,
        })
        fom_aps = 0.0
        if ok_aps:
            edges_aps = read_output_edges(args.width, args.height)
            fom_aps = pratt_fom(ground_truth, edges_aps, alpha=args.alpha)
            print(f"         FOM = {fom_aps:.4f}")
        else:
            print("         FALHA na simulação — FOM=0", file=sys.stderr)

        results.append({
            "noise_pct":  noise_pct,
            "sigma_fixo": 1.3,           # σ hardcoded no testbench
            "th_h_fixo":  FIXED_TH_H,
            "th_l_fixo":  FIXED_TH_L,
            "fom_fixo":   round(fom_fixo, 6),
            "sigma_aps":  sigma_aps,
            "th_h_aps":   th_h_aps,
            "fom_aps":    round(fom_aps, 6),
        })

    # ------------------------------------------------------------------
    # 3. Salvar CSV
    # ------------------------------------------------------------------
    csv_path = Path(args.csv_out)
    fieldnames = ["noise_pct", "sigma_fixo", "th_h_fixo", "th_l_fixo",
                  "fom_fixo", "sigma_aps", "th_h_aps", "fom_aps"]
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(results)
    print(f"\n[OK] CSV salvo em: {csv_path}")

    # ------------------------------------------------------------------
    # 4. Gráfico FOM vs. nível de ruído
    # ------------------------------------------------------------------
    x         = [r["noise_pct"] for r in results]
    fom_fixos = [r["fom_fixo"]  for r in results]
    fom_apss  = [r["fom_aps"]   for r in results]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(x, fom_fixos, marker="s", linewidth=1.8, markersize=6,
            color="#CC4444", linestyle="--", label=f"Parâmetros fixos (TH_H={FIXED_TH_H})")
    ax.plot(x, fom_apss,  marker="o", linewidth=2.0, markersize=6,
            color="#1A7A5C", linestyle="-",  label=f"APS (MDP={args.mdp}%)")

    ax.set_xlabel("Nível de ruído (%)", fontsize=12)
    ax.set_ylabel("Figure of Merit de Pratt (FOM)", fontsize=12)
    ax.set_title(
        f"Qualidade de Detecção de Bordas: Parâmetros Fixos vs. APS\n"
        f"Imagem: {img_path.name} — {args.width}×{args.height} px"
        f" — α={args.alpha:.3f}",
        fontsize=11, fontweight="bold"
    )
    ax.set_xticks(x)
    ax.set_xlim(0, 75)
    ax.set_ylim(0, 1.05)
    ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.2f}"))
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.legend(fontsize=11)

    # Linha de referência: FOM mínimo aceitável (opcional)
    ax.axhline(0.5, color="gray", linewidth=0.8, linestyle=":", alpha=0.7)
    ax.text(72, 0.515, "FOM=0.5", fontsize=9, color="gray", ha="right")

    plt.tight_layout()
    fig_path = Path(args.fig_out)
    plt.savefig(str(fig_path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[OK] Gráfico salvo em: {fig_path}")

    # ------------------------------------------------------------------
    # 5. Resumo no terminal
    # ------------------------------------------------------------------
    print(f"\n{'='*58}")
    print(f"  {'Ruído':>5}  {'FOM Fixo':>10}  {'FOM APS':>10}  {'Ganho':>8}")
    print(f"{'─'*58}")
    for r in results:
        ganho = r["fom_aps"] - r["fom_fixo"]
        print(f"  {r['noise_pct']:>4d}%  {r['fom_fixo']:>10.4f}  {r['fom_aps']:>10.4f}"
              f"  {ganho:>+8.4f}")
    print(f"{'='*58}")


if __name__ == "__main__":
    main()
