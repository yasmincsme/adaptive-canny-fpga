#!/usr/bin/env python3
"""
Conversor de Imagem (PNG/JPG/...) para o formato .hex do testbench do Canny APS
================================================================================
Lê uma imagem colorida (BGR/RGB) suportada pelo OpenCV e grava:

  - entrada_canny.hex   → um pixel RGB de 24 bits por linha (%06X, ordem
                          {R,G,B}), em ordem row-major, consumido via
                          $readmemh pela testbench tb_canny_top_module.v.
                          A conversão para escala de cinza é feita dentro do
                          próprio datapath (rgb_gray_average.v), não aqui.
  - image_params.vh     → `define IMG_WIDTH / IMG_HEIGHT com as dimensões
                          reais da imagem, incluído pela testbench para
                          dimensionar os parâmetros IMG_WIDTH/IMG_HEIGHT
                          sem precisar editar o arquivo .v manualmente.

Por padrão a imagem é redimensionada para 512x512 (resolução alvo do
projeto, parâmetro IMG_WIDTH/IMG_HEIGHT default do canny_top_module).
Use --width/--height para outra resolução, ou --no_resize para manter o
tamanho original da imagem.

Uso:
  python3 scripts/png_to_hex.py caminho/para/imagem.png
  python3 scripts/png_to_hex.py imagem.png --width 128 --height 128
  python3 scripts/png_to_hex.py imagem.png --no_resize
"""

import argparse
import sys
from pathlib import Path

import cv2

REPO_ROOT = Path(__file__).parent.parent
DEFAULT_HEX_PATH = REPO_ROOT / "entrada_canny.hex"
DEFAULT_VH_PATH = REPO_ROOT / "src" / "Canny_top" / "image_params.vh"
DEFAULT_SIZE = 512


def main():
    parser = argparse.ArgumentParser(
        description="Converte uma imagem colorida para o .hex de entrada do Canny APS"
    )
    parser.add_argument("image_path", type=str, help="Caminho da imagem de entrada")
    parser.add_argument("--width", type=int, default=DEFAULT_SIZE,
                         help=f"Redimensiona a imagem para esta largura (padrão: {DEFAULT_SIZE})")
    parser.add_argument("--height", type=int, default=DEFAULT_SIZE,
                         help=f"Redimensiona a imagem para esta altura (padrão: {DEFAULT_SIZE})")
    parser.add_argument("--no_resize", action="store_true",
                         help="Mantém o tamanho original da imagem (ignora --width/--height)")
    parser.add_argument("--hex_out", type=str, default=str(DEFAULT_HEX_PATH),
                         help=f"Caminho de saída do .hex (padrão: {DEFAULT_HEX_PATH})")
    parser.add_argument("--vh_out", type=str, default=str(DEFAULT_VH_PATH),
                         help=f"Caminho de saída do cabeçalho Verilog (padrão: {DEFAULT_VH_PATH})")
    args = parser.parse_args()

    img_path = Path(args.image_path)
    if not img_path.is_file():
        print(f"ERRO: imagem nao encontrada: {img_path}", file=sys.stderr)
        sys.exit(1)

    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR)  # BGR, 3 canais
    if img is None:
        print(f"ERRO: nao foi possivel ler a imagem (formato nao suportado?): {img_path}",
              file=sys.stderr)
        sys.exit(1)

    if not args.no_resize:
        img = cv2.resize(img, (args.width, args.height), interpolation=cv2.INTER_AREA)

    height, width = img.shape[:2]

    hex_out = Path(args.hex_out)
    hex_out.parent.mkdir(parents=True, exist_ok=True)
    with open(hex_out, "w") as f:
        for row in range(height):
            for col in range(width):
                b, g, r = img[row, col]  # OpenCV le como BGR
                f.write(f"{r:02X}{g:02X}{b:02X}\n")

    vh_out = Path(args.vh_out)
    vh_out.parent.mkdir(parents=True, exist_ok=True)
    with open(vh_out, "w") as f:
        f.write("// Gerado automaticamente por scripts/png_to_hex.py -- nao editar a mao.\n")
        f.write(f"// Fonte: {img_path.name}\n")
        f.write(f"`define IMG_WIDTH  {width}\n")
        f.write(f"`define IMG_HEIGHT {height}\n")

    print(f"Imagem '{img_path.name}' ({width}x{height}, RGB) convertida com sucesso.")
    print(f"  {hex_out}")
    print(f"  {vh_out}")
    print(f"\nDimensao de saida esperada apos o pipeline (perda medida "
          f"empiricamente: -6 largura, -5 altura): {width - 6}x{height - 5}")


if __name__ == "__main__":
    main()
