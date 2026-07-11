#!/usr/bin/env python3
"""
Conversor do .hex de saida do Canny APS para uma imagem PNG
=============================================================
Lê saida_canny.hex (um valor %02X por linha, gerado pela testbench
tb_canny_top_module.v) e reconstrói a imagem de bordas detectadas.

As dimensões de saída são lidas de image_params.vh (gerado por
scripts/png_to_hex.py) e ajustadas pela perda medida empiricamente
(-6 de largura, -5 de altura -- ver comentário de OUT_WIDTH/OUT_HEIGHT em
tb_canny_top_module.v), a menos que --width/--height sejam informados
explicitamente.

Uso:
  python3 scripts/hex_to_png.py
  python3 scripts/hex_to_png.py --hex saida_canny.hex --out bordas.png
"""

import argparse
import re
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).parent.parent
BUILD_DIR = REPO_ROOT / "build"
DEFAULT_HEX_PATH = BUILD_DIR / "saida_canny.hex"
DEFAULT_VH_PATH = BUILD_DIR / "image_params.vh"
DEFAULT_OUT_PATH = BUILD_DIR / "saida_canny.png"

WIDTH_LOSS = 6   # 3 janelas 3x3 em cascata (Sobel, NMS, Histerese) descartam 2 colunas/linha cada
HEIGHT_LOSS = 5  # Preenchimento inicial do pipeline (dominado pela janela 7x7 do Gauss)


def read_dims_from_vh(vh_path):
    text = Path(vh_path).read_text()
    w_match = re.search(r"`define\s+IMG_WIDTH\s+(\d+)", text)
    h_match = re.search(r"`define\s+IMG_HEIGHT\s+(\d+)", text)
    if not w_match or not h_match:
        return None
    return int(w_match.group(1)), int(h_match.group(1))


def main():
    parser = argparse.ArgumentParser(
        description="Converte o .hex de saida do Canny APS para PNG"
    )
    parser.add_argument("--hex", type=str, default=str(DEFAULT_HEX_PATH),
                         help=f"Caminho do .hex de saida (padrao: {DEFAULT_HEX_PATH})")
    parser.add_argument("--out", type=str, default=str(DEFAULT_OUT_PATH),
                         help=f"Caminho da imagem PNG de saida (padrao: {DEFAULT_OUT_PATH})")
    parser.add_argument("--vh", type=str, default=str(DEFAULT_VH_PATH),
                         help=f"Cabecalho Verilog com as dimensoes da imagem de entrada "
                              f"(padrao: {DEFAULT_VH_PATH})")
    parser.add_argument("--width", type=int, default=None,
                         help="Largura da imagem de SAIDA (sobrepoe image_params.vh)")
    parser.add_argument("--height", type=int, default=None,
                         help="Altura da imagem de SAIDA (sobrepoe image_params.vh)")
    args = parser.parse_args()

    if args.width is not None and args.height is not None:
        out_width, out_height = args.width, args.height
    else:
        vh_path = Path(args.vh)
        if not vh_path.is_file():
            print(f"ERRO: {vh_path} nao encontrado. Rode scripts/png_to_hex.py primeiro "
                  f"ou informe --width/--height.", file=sys.stderr)
            sys.exit(1)
        dims = read_dims_from_vh(vh_path)
        if dims is None:
            print(f"ERRO: nao foi possivel ler IMG_WIDTH/IMG_HEIGHT de {vh_path}", file=sys.stderr)
            sys.exit(1)
        in_width, in_height = dims
        out_width, out_height = in_width - WIDTH_LOSS, in_height - HEIGHT_LOSS

    hex_path = Path(args.hex)
    if not hex_path.is_file():
        print(f"ERRO: {hex_path} nao encontrado. Rode a simulacao primeiro.", file=sys.stderr)
        sys.exit(1)

    values = [int(line.strip(), 16) for line in hex_path.read_text().splitlines() if line.strip()]

    expected = out_width * out_height
    if len(values) != expected:
        print(f"AVISO: {len(values)} pixeis validos lidos, esperado {expected} "
              f"({out_width}x{out_height}). Verifique se a simulacao rodou ate o fim "
              f"(injecao de pixeis de flush suficiente).", file=sys.stderr)

    usable = min(len(values), expected)
    img = np.zeros(expected, dtype=np.uint8)
    img[:usable] = values[:usable]
    img = img.reshape(out_height, out_width)

    out_path = Path(args.out)
    cv2.imwrite(str(out_path), img)
    print(f"Imagem de bordas ({out_width}x{out_height}) salva em: {out_path}")


if __name__ == "__main__":
    main()
