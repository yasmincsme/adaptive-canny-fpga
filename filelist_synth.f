// Lista de arquivos RTL para SÍNTESE do canny_top_module no Genus.
//
// É a mesma lista de filelist_canny_top.f, mas SEM a testbench --
// synth/scripts/run_synth.tcl lê este arquivo (não o filelist_canny_top.f,
// que é só para simulação com iverilog/xrun).
//
// Se você adicionar/remover um módulo do datapath, atualize os três
// arquivos junto (filelist.f, filelist_canny_top.f, filelist_synth.f) --
// não há um único lugar de verdade ainda.

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
