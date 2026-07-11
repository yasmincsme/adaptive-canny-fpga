// Lista de arquivos dedicada ao teste funcional do pipeline completo de
// detecção de bordas (canny_top_module + tb_canny_top_module).
//
// Separada do filelist.f principal de propósito porque este é usado para
// alternar entre vários testbenches (SPI, pré-processamento, módulos
// isolados) por outros membros da equipe -- usar essa lista dedicada evita
// que o teste de detecção de borda quebre quando alguém troca o testbench
// ativo em filelist.f.
//
// Uso: scripts/run_batch_edge_tests.py (compila com iverilog -f este arquivo)

src/gradient/abs_value.v
src/gradient/gradient_datpath.v
src/gradient/gradient_decision_tree.v
src/gradient/mag_aprox.v
src/gradient/sobel_filter.v
src/multiplier/cla_4bit.v
src/multiplier/cla_adder.v
src/multiplier/csa_16bit.v
src/multiplier/full_adder.v
src/multiplier/gauss_smoothing_datapath.v
src/multiplier/gauss_uc.v
src/multiplier/half_adder.v
src/multiplier/wallace_8x8_unsigned.v
src/window/line_buffer.v
src/window/sliding_window_3x3.v
src/window/sliding_window_7x7_flex.v
src/window/sliding_window_fsm.v
src/window/nms_window_buffer.v
src/NMS/nms_combinational.v
src/thresholding/double_threshold.v
src/thresholding/hysteresis_logic.v
src/thresholding/hysteresis_datapath.v
src/noise_estimator/noise_estimator_uc.v
src/noise_estimator/noise_estimator.v
src/config_table/config_table.v
src/rgb_gray_average.v
src/Canny_top/canny_top_module.v
src/Canny_top/tb_canny_top_module.v
