#!/usr/bin/env python3
"""
Lê build/aps_efficacy.csv e imprime as linhas prontas para substituir
os '--' na Tabela IV-C de resultados.tex.

Uso:
  python3 scripts/fill_fom_table.py
  python3 scripts/fill_fom_table.py --csv build/aps_efficacy.csv --tex artigo/resultados.tex
"""
import argparse
import csv
import json
import re
from pathlib import Path

REPO_ROOT   = Path(__file__).parent.parent
CONFIG_JSON = REPO_ROOT / "src" / "config_table" / "config_table.json"

SIGMA_MAP = {
    5:  (1.3, 38),
    10: (1.3, 38),
    15: (1.3, 38),
    20: (1.3, 38),
    25: (1.3, 38),
    30: (1.3, 38),
    35: (1.5, 64),
    40: (1.5, 64),
    45: (1.5, 64),
    50: (1.5, 64),
    55: (1.5, 64),
    60: (1.5, 64),
    65: (1.5, 100),
    70: (1.5, 100),
}


def load_csv(path: Path):
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append({
                "noise_pct": int(r["noise_pct"]),
                "fom_fixo":  float(r["fom_fixo"]),
                "fom_aps":   float(r["fom_aps"]),
            })
    return rows


def print_latex_rows(rows):
    print("% ---- Linhas para a Tabela tab:fom_resultados ----")
    for r in rows:
        n   = r["noise_pct"]
        ff  = r["fom_fixo"]
        fa  = r["fom_aps"]
        g   = fa - ff
        sig, th_h = SIGMA_MAP.get(n, ("?", "?"))
        sign = "+" if g >= 0 else ""
        print(f"        {n:>3d}\\% & {sig:.1f} & {th_h:>3d} & "
              f"{ff:.4f} & {fa:.4f} & {sign}{g:.4f} \\\\")


def patch_tex(tex_path: Path, rows):
    """Substitui os '--' na tabela LaTeX pelos valores reais."""
    text = tex_path.read_text()
    new_lines = []
    for r in rows:
        n   = r["noise_pct"]
        ff  = r["fom_fixo"]
        fa  = r["fom_aps"]
        g   = fa - ff
        sig, th_h = SIGMA_MAP.get(n, ("?", "?"))
        sign = "+" if g >= 0 else ""
        new_lines.append(
            f"        {n:>3d}\\% & {sig:.1f} & {th_h:>3d} & "
            f"{ff:.4f} & {fa:.4f} & {sign}{g:.4f} \\\\"
        )

    block = "\n".join(new_lines)
    # Localiza o bloco de -- dentro da tabela e substitui
    old_block_pattern = re.compile(
        r"( 5\\% & 1,3 &  38 & -- & -- & --.*?70\\% & 1,5 & 100 & -- & -- & --)",
        re.DOTALL
    )
    if old_block_pattern.search(text):
        text = old_block_pattern.sub(block, text)
        tex_path.write_text(text)
        print(f"[OK] Tabela atualizada em: {tex_path}")
    else:
        print("[AVISO] Padrão de '--' não encontrado — imprimir linhas manualmente:")
        print(block)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", default="build/aps_efficacy.csv")
    parser.add_argument("--tex", default="artigo/resultados.tex")
    parser.add_argument("--print-only", action="store_true",
                        help="Apenas imprime as linhas, sem editar o .tex")
    args = parser.parse_args()

    csv_path = REPO_ROOT / args.csv
    tex_path = REPO_ROOT / args.tex

    if not csv_path.exists():
        print(f"ERRO: {csv_path} não encontrado. Execute scripts/aps_efficacy.py primeiro.")
        return

    rows = load_csv(csv_path)
    print_latex_rows(rows)

    if not args.print_only and tex_path.exists():
        patch_tex(tex_path, rows)


if __name__ == "__main__":
    main()
