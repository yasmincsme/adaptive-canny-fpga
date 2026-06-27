#!/usr/bin/env python3
"""
Gerador da Tabela de Configuração para o Canny APS
===================================================
Implementa o Algoritmo 1 (PS Selection) do artigo:
  Kalbasi & Nikmehr, "Noise-Robust, Reconfigurable Canny Edge Detection
  and Its Hardware Realization", IEEE Access, 2020.

Procedimento (Secção III.D):
  1. Carregar imagens de referência (escala de cinza).
  2. Para cada imagem, gerar versões ruidosas (5% a 70%, passo 5%).
  3. Aplicar Canny com 700 combinações de (Sigma, TH_H) em cada versão.
  4. Calcular Pco (percentagem de bordas correctamente detectadas).
  5. Fazer a média dos Pco entre todas as imagens.
  6. Para cada par (noise, MDP), seleccionar o PS com menor Sigma
     que satisfaça Pco ≥ MDP; caso contrário, escolher o MAP.

Saída:
  - config_table.mem  → ficheiro $readmemh para o módulo Verilog
  - config_table.json → dados legíveis para inspecção

Utilização:
  python3 generate_config_table.py --images_dir ./images --output_dir ../src/config_table

Dependências: numpy, opencv-python (pip install numpy opencv-python)
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

# ============================================================================
# PARÂMETROS DA ENUMERAÇÃO (Tabela 2 do artigo)
# ============================================================================
SIGMA_VALUES = [round(0.1 + i * 0.2, 1) for i in range(14)]  # 0.1 a 2.7
THH_VALUES   = [round(0.01 + i * 0.02, 2) for i in range(50)] # 0.01 a 0.99
NOISE_LEVELS = list(range(5, 75, 5))                            # 5% a 70%
MDP_VALUES   = [91, 92, 93, 94]                                 # MDP (%)

# Sigma → kernel_sel (2 bits) para o hardware
# Apenas 4 valores distintos são utilizados na configuração final
SIGMA_TO_KERNEL = {0.9: 0, 1.1: 1, 1.3: 2, 1.5: 3}
KERNEL_SIGMAS = [0.9, 1.1, 1.3, 1.5]


def kernel_size_from_sigma(sigma):
    """Calcula o tamanho do kernel Gaussiano pela regra dos 3-sigma."""
    ksize = int(np.ceil(6 * sigma + 1))
    if ksize % 2 == 0:
        ksize += 1
    return max(ksize, 3)


def add_gaussian_noise(image, noise_percent):
    """Adiciona ruído Gaussiano com intensidade dada (% de 255)."""
    std_dev = (noise_percent / 100.0) * 255
    noise = np.random.normal(0, std_dev, image.shape)
    noisy = np.clip(image.astype(np.float64) + noise, 0, 255)
    return noisy.astype(np.uint8)


def apply_canny(image, sigma, th_h):
    """Aplica suavização Gaussiana + Canny."""
    th_l = 0.4 * th_h
    ksize = kernel_size_from_sigma(sigma)

    smoothed = cv2.GaussianBlur(image, (ksize, ksize), sigma)

    t_high = max(1, min(255, int(th_h * 255)))
    t_low  = max(1, min(t_high - 1, int(th_l * 255)))

    return cv2.Canny(smoothed, t_low, t_high)


def compute_pco(edge_new, edge_ref):
    """Pco = CNC / COC  (Eq. 2 do artigo)."""
    coc = np.count_nonzero(edge_ref)
    if coc == 0:
        return 0.0
    cnc = np.count_nonzero(np.logical_and(edge_new > 0, edge_ref > 0))
    return (cnc / coc) * 100.0


def load_images(images_dir):
    """Carrega imagens em escala de cinza."""
    images = []
    exts = ('*.png', '*.jpg', '*.jpeg', '*.bmp', '*.tif', '*.tiff', '*.pgm')
    for ext in exts:
        for path in sorted(Path(images_dir).glob(ext)):
            img = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
            if img is not None:
                images.append((path.name, img))
    return images


def compute_reference_edges(images):
    """Edge maps de referência com o Canny 'Original' (σ=1.0, TH_H=0.20)."""
    ref_sigma = 1.0
    ref_th_h  = 0.20
    refs = []
    for name, img in images:
        refs.append(apply_canny(img, ref_sigma, ref_th_h))
    return refs


def enumerate_ps(images, ref_edges, verbose=True):
    """
    Fase de enumeração: calcula Pco médio para cada combinação
    (noise_level, sigma, th_h).

    Retorna: avg_pco[noise_idx][ps_idx]
    """
    num_images = len(images)
    num_ps = len(SIGMA_VALUES) * len(THH_VALUES)  # 14 × 50 = 700

    avg_pco = np.zeros((len(NOISE_LEVELS), num_ps))

    np.random.seed(42)

    for n_idx, noise_pct in enumerate(NOISE_LEVELS):
        if verbose:
            print(f"  Ruído {noise_pct:2d}% ...", end="", flush=True)

        for img_idx, ((name, img), ref_edge) in enumerate(
            zip(images, ref_edges)
        ):
            noisy = add_gaussian_noise(img, noise_pct)

            ps_idx = 0
            for sigma in SIGMA_VALUES:
                for th_h in THH_VALUES:
                    edge = apply_canny(noisy, sigma, th_h)
                    pco  = compute_pco(edge, ref_edge)
                    avg_pco[n_idx][ps_idx] += pco
                    ps_idx += 1

        avg_pco[n_idx] /= num_images

        if verbose:
            peak = np.max(avg_pco[n_idx])
            print(f"  MAP = {peak:.1f}%")

    return avg_pco


def select_parameters(avg_pco):
    """
    Algoritmo 1 (PS Selection): para cada (MDP, noise_level), selecciona
    o PS com menor Sigma que satisfaça Pco ≥ MDP. Caso contrário, MAP.

    Retorna: config[mdp][noise_pct] = (sigma, th_h)
    """
    config = {}

    for mdp in MDP_VALUES:
        config[mdp] = {}

        for n_idx, noise_pct in enumerate(NOISE_LEVELS):
            candidates = []

            ps_idx = 0
            for s_idx, sigma in enumerate(SIGMA_VALUES):
                for t_idx, th_h in enumerate(THH_VALUES):
                    if avg_pco[n_idx][ps_idx] >= mdp:
                        candidates.append((sigma, th_h, ps_idx))
                    ps_idx += 1

            if candidates:
                best = min(candidates, key=lambda x: (x[0], -x[1]))
                selected_sigma, selected_th_h = best[0], best[1]
            else:
                best_ps = int(np.argmax(avg_pco[n_idx]))
                s_idx = best_ps // len(THH_VALUES)
                t_idx = best_ps %  len(THH_VALUES)
                selected_sigma = SIGMA_VALUES[s_idx]
                selected_th_h  = THH_VALUES[t_idx]

            config[mdp][noise_pct] = (selected_sigma, selected_th_h)

    return config


def snap_sigma(sigma):
    """Aproxima o Sigma ao valor de hardware mais próximo (0.9, 1.1, 1.3, 1.5)."""
    return min(KERNEL_SIGMAS, key=lambda x: abs(x - sigma))


def float_to_q016(value):
    """Converte um float ∈ [0, 1) para ponto fixo Q0.16 (16 bits fraccionários)."""
    return int(round(value * 65536)) & 0xFFFF


def generate_mem_file(config, output_path):
    """
    Gera o ficheiro .mem para $readmemh.

    Formato de cada palavra (34 bits codificados em 9 dígitos hex):
      [33:32] kernel_sel  (2 bits)
      [31:16] th_high     (16 bits, Q0.16)
      [15:0]  th_low      (16 bits, Q0.16)

    Endereçamento: addr = {noise_idx[3:0], mdp_idx[1:0]}
      noise_idx: 0 = 5%, 1 = 10%, ..., 13 = 70%
      mdp_idx:   0 = 91%, 1 = 92%, 2 = 93%, 3 = 94%
    """
    lines = []

    for n_idx, noise_pct in enumerate(NOISE_LEVELS):
        for m_idx, mdp in enumerate(MDP_VALUES):
            sigma, th_h = config[mdp][noise_pct]
            sigma_hw = snap_sigma(sigma)
            kernel_sel = SIGMA_TO_KERNEL[sigma_hw]
            th_l = 0.4 * th_h

            th_h_fp = float_to_q016(th_h)
            th_l_fp = float_to_q016(th_l)

            word = (kernel_sel << 32) | (th_h_fp << 16) | th_l_fp
            addr = (n_idx << 2) | m_idx

            lines.append(f"{word:09X}  // addr={addr:02d} N={noise_pct:2d}% "
                         f"MDP={mdp}% σ={sigma_hw} "
                         f"TH_H={th_h:.2f} TH_L={th_l:.3f}")

    with open(output_path, 'w') as f:
        f.write("// Tabela de Configuração APS — gerada por generate_config_table.py\n")
        f.write("// Formato: {kernel_sel[1:0], th_high[15:0], th_low[15:0]}\n")
        f.write("// Endereço: {noise_idx[3:0], mdp_idx[1:0]}\n\n")
        for line in lines:
            f.write(line + "\n")

    return lines


def generate_json(config, output_path):
    """Exporta a tabela em JSON para inspecção."""
    out = {}
    for mdp in MDP_VALUES:
        out[str(mdp)] = {}
        for noise_pct in NOISE_LEVELS:
            sigma, th_h = config[mdp][noise_pct]
            sigma_hw = snap_sigma(sigma)
            out[str(mdp)][str(noise_pct)] = {
                "sigma": sigma,
                "sigma_hw": sigma_hw,
                "kernel_sel": SIGMA_TO_KERNEL[sigma_hw],
                "th_h": round(th_h, 4),
                "th_l": round(0.4 * th_h, 4),
            }

    with open(output_path, 'w') as f:
        json.dump(out, f, indent=2)


def generate_default_table():
    """
    Tabela por omissão baseada nos valores publicados na Table 4 do artigo.
    Utilizada quando não há imagens disponíveis para a enumeração.
    """
    config = {}

    # MDP=94%
    config[94] = dict(zip(NOISE_LEVELS, [
        (1.3, 0.15), (1.3, 0.19), (1.3, 0.21), (1.5, 0.19),
        (1.5, 0.19), (1.5, 0.25), (1.5, 0.25), (1.5, 0.25),
        (1.5, 0.29), (1.5, 0.29), (1.5, 0.33), (1.5, 0.37),
        (1.5, 0.41), (1.5, 0.39),
    ]))

    # MDP=93%
    config[93] = dict(zip(NOISE_LEVELS, [
        (1.3, 0.21), (1.3, 0.25), (1.3, 0.27), (1.3, 0.23),
        (1.3, 0.23), (1.5, 0.25), (1.5, 0.25), (1.5, 0.25),
        (1.5, 0.29), (1.5, 0.29), (1.5, 0.31), (1.5, 0.33),
        (1.5, 0.37), (1.5, 0.39),
    ]))

    # MDP=92%
    config[92] = dict(zip(NOISE_LEVELS, [
        (1.1, 0.21), (1.1, 0.23), (1.1, 0.23), (1.1, 0.23),
        (1.1, 0.29), (1.3, 0.25), (1.3, 0.29), (1.3, 0.29),
        (1.3, 0.33), (1.3, 0.37), (1.5, 0.33), (1.5, 0.37),
        (1.5, 0.37), (1.5, 0.39),
    ]))

    # MDP=91%
    config[91] = dict(zip(NOISE_LEVELS, [
        (0.9, 0.25), (1.1, 0.27), (1.1, 0.27), (1.1, 0.29),
        (1.1, 0.29), (1.1, 0.31), (1.1, 0.33), (1.1, 0.35),
        (1.3, 0.37), (1.3, 0.37), (1.5, 0.37), (1.5, 0.37),
        (1.5, 0.41), (1.5, 0.39),
    ]))

    return config


def main():
    parser = argparse.ArgumentParser(
        description="Gerador da Tabela de Configuração APS Canny"
    )
    parser.add_argument(
        "--images_dir", type=str, default=None,
        help="Directório com imagens de referência (escala de cinza). "
             "Se omitido, usa os valores por omissão da Table 4 do artigo."
    )
    parser.add_argument(
        "--output_dir", type=str,
        default=str(Path(__file__).parent.parent / "src" / "config_table"),
        help="Directório de saída para os ficheiros .mem e .json"
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.images_dir is None:
        print("Sem directório de imagens — a usar valores por omissão (Table 4).")
        config = generate_default_table()
    else:
        images = load_images(args.images_dir)
        if not images:
            print(f"ERRO: nenhuma imagem encontrada em '{args.images_dir}'",
                  file=sys.stderr)
            sys.exit(1)

        print(f"Carregadas {len(images)} imagens: "
              f"{', '.join(n for n, _ in images)}")

        print("\n[1/3] A calcular edge maps de referência...")
        ref_edges = compute_reference_edges(images)

        print("\n[2/3] A enumerar 700 PS × 14 níveis de ruído...")
        avg_pco = enumerate_ps(images, ref_edges)

        print("\n[3/3] A seleccionar parâmetros óptimos...")
        config = select_parameters(avg_pco)

    mem_path  = output_dir / "config_table.mem"
    json_path = output_dir / "config_table.json"

    lines = generate_mem_file(config, mem_path)
    generate_json(config, json_path)

    print(f"\nFicheiros gerados:")
    print(f"  {mem_path}")
    print(f"  {json_path}")
    print(f"\nEntradas da tabela ({len(lines)}):")
    for line in lines:
        print(f"  {line}")


if __name__ == "__main__":
    main()
