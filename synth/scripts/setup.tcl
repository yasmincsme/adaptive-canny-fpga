########################################################################
# setup.tcl -- configuracao de tecnologia para a sintese do
#              canny_top_module no Genus.
#
# PREENCHER ANTES DE RODAR: ainda nao escolhemos uma PDK/biblioteca de
# celulas padrao para este projeto, entao os caminhos abaixo estao vazios
# de proposito. run_synth.tcl aborta com um aviso claro se voce esquecer
# de preencher isto.
#
# Exemplo (NanGate FreePDK45, comum em fluxos academicos com Genus):
#   set LIB_DIR    "/caminho/para/NanGateFreePDK45/liberty"
#   set TARGET_LIBS [list \
#       "$LIB_DIR/NangateOpenCellLibrary_typical.lib" \
#   ]
########################################################################

# ------------------------------------------------------------------
# 1. BIBLIOTECA DE CELULAS PADRAO (Liberty)
# ------------------------------------------------------------------
set LIB_DIR      ""
set TARGET_LIBS  {}

# Corners adicionais (best/worst case), se/quando formos rodar STA
# multi-corner. Deixe vazio por enquanto -- so o corner "typical" acima
# ja e suficiente para uma primeira sintese funcional.
set MIN_LIBS     {}
set MAX_LIBS     {}

if {$LIB_DIR eq "" || [llength $TARGET_LIBS] == 0} {
    puts "########################################################################"
    puts "# ERRO: synth/scripts/setup.tcl nao esta configurado."
    puts "#"
    puts "# Preencha LIB_DIR e TARGET_LIBS com o caminho da PDK/biblioteca de"
    puts "# celulas padrao (.lib) que voce vai usar antes de rodar run_synth.tcl."
    puts "########################################################################"
    return -code error "setup.tcl: LIB_DIR/TARGET_LIBS nao configurados"
}

set_db library $TARGET_LIBS

# ------------------------------------------------------------------
# 2. DIRETORIOS DE SAIDA
# ------------------------------------------------------------------
# Caminhos relativos a synth/scripts/, de onde o Genus deve ser invocado.
set OUT_DIR    "../outputs"
set REPORT_DIR "../reports"

file mkdir $OUT_DIR
file mkdir $REPORT_DIR

# ------------------------------------------------------------------
# 3. OPCOES GERAIS
# ------------------------------------------------------------------
set_db information_level        7
set_db hdl_error_on_blackbox    true

# canny_top_module usa parametros (IMG_WIDTH, DATA_WIDTH, MAG_WIDTH,
# GRAD_MAG_FULL_SCALE) com valores por omissao adequados para sintese
# (ver canny_top_module.v) -- nao deveria ser preciso sobrescreve-los,
# mas se precisar, use `elaborate canny_top_module -parameters {...}`
# em vez de editar o RTL.
