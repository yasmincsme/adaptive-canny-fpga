########################################################################
# run_synth.tcl -- fluxo principal de sintese do canny_top_module no Genus
#
# NAO EXECUTAR AINDA: preencha synth/scripts/setup.tcl (LIB_DIR/
# TARGET_LIBS) primeiro -- sem isso, este script para logo no source
# abaixo com um erro claro.
#
# Uso pretendido (a partir de synth/scripts/):
#   genus -legacy_ui -files run_synth.tcl -log ../logs/run_synth
#
# Os comandos abaixo seguem a sintaxe Genus tipica (read_hdl/elaborate/
# syn_generic/syn_map/syn_opt + redirect para relatorios), mas nao foram
# testados neste ambiente -- confira contra a versao do Genus instalada
# antes de rodar de verdade (flags como write_db -to_file podem variar
# entre releases).
########################################################################

source setup.tcl

# ------------------------------------------------------------------
# 1. LEITURA DO RTL
# ------------------------------------------------------------------
# Le ../../filelist_synth.f (a mesma lista de filelist_canny_top.f, sem a
# testbench) filtrando comentarios ('//', '#') e linhas em branco -- mesma
# ideia do `grep -v '^//'` usado no fluxo de simulacao com iverilog
# (ver config.txt).
proc read_filelist {path} {
    set fh [open $path r]
    set files {}
    while {[gets $fh line] >= 0} {
        set trimmed [string trim $line]
        if {$trimmed eq ""} { continue }
        if {[string match "//*" $trimmed]} { continue }
        if {[string match "#*" $trimmed]} { continue }
        lappend files "../../$trimmed"
    }
    close $fh
    return $files
}

set RTL_FILES [read_filelist "../../filelist_synth.f"]
read_hdl -sv $RTL_FILES

# ------------------------------------------------------------------
# 2. ELABORACAO
# ------------------------------------------------------------------
# config_table.v carrega src/config_table/config_table.mem via $readmemh
# com caminho relativo a raiz do repositorio -- por isso a convencao de
# invocar o Genus a partir de synth/scripts/ (mesma logica do MEM_FILE
# usado na simulacao, ver config_table.v). Se preferir rodar de outro
# diretorio, sobrescreva o parametro:
#   elaborate canny_top_module -parameters {MEM_FILE <caminho absoluto>}
#
# TODO/RISCO A VERIFICAR NA PRIMEIRA RODADA: config_table.v declara a ROM
# como `reg [33:0] rom [0:55]` com $readmemh -- confirmar que o Genus
# infere isso como logica combinacional/mux (ROM em standard-cell), e nao
# como uma memoria que precisa de um macro/compilador de memoria que nao
# temos. Para uma ROM de 56x34 isso costuma sintetizar bem como logica,
# mas vale checar o log de elaboracao antes de confiar no relatorio de
# area.
elaborate canny_top_module

check_design -unresolved

# ------------------------------------------------------------------
# 3. RESTRICOES
# ------------------------------------------------------------------
read_sdc constraints.sdc

# ------------------------------------------------------------------
# 4. SINTESE (generica -> mapeamento tecnologico -> otimizacao)
# ------------------------------------------------------------------
syn_generic
syn_map
syn_opt

# ------------------------------------------------------------------
# 5. RELATORIOS
# ------------------------------------------------------------------
redirect $REPORT_DIR/check_design.rpt { check_design }
redirect $REPORT_DIR/area.rpt         { report_area }
redirect $REPORT_DIR/gates.rpt        { report_gates }
redirect $REPORT_DIR/timing.rpt       { report_timing }
redirect $REPORT_DIR/power.rpt        { report_power }

# ------------------------------------------------------------------
# 6. SAIDAS (netlist + SDC pos-sintese + banco de dados do Genus)
# ------------------------------------------------------------------
redirect $OUT_DIR/canny_top_module_netlist.v { write_hdl -mapped }
redirect $OUT_DIR/canny_top_module.sdc       { write_sdc }
write_db -to_file $OUT_DIR/canny_top_module.db

puts "########################################################################"
puts "# Sintese concluida."
puts "# Relatorios : $REPORT_DIR (area.rpt, timing.rpt, power.rpt, gates.rpt)"
puts "# Saidas     : $OUT_DIR (netlist + sdc + db)"
puts "########################################################################"
