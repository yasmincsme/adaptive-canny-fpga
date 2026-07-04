`timescale 1ns / 1ps

module canny_top_module #(
    parameter IMG_WIDTH   = 512,
    parameter DATA_WIDTH  = 8,
    parameter MAG_WIDTH   = 12,
    // Escala usada para converter os limiares fracionários Q0.16 da tabela
    // de configuração (config_table) para o domínio de magnitude de
    // MAG_WIDTH bits: thresh_bits = round(th_qfrac * GRAD_MAG_FULL_SCALE).
    // Calibrado empiricamente contra fotos reais nesta implementação (Sobel
    // sobre diferenças de píxeis de 8 bits + aproximação diagonal em
    // mag_approx.v): a magnitude resultante para gradientes fotográficos
    // típicos fica na casa de poucas centenas, bem abaixo do valor teórico
    // de fundo de escala 2^MAG_WIDTH-1. Se o datapath de gradiente mudar,
    // recalibre este valor.
    parameter GRAD_MAG_FULL_SCALE = 256
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Interface de Entrada de Vídeo (RGB — convertido para escala de cinza internamente)
    input  wire [DATA_WIDTH-1:0] pixel_r_in,
    input  wire [DATA_WIDTH-1:0] pixel_g_in,
    input  wire [DATA_WIDTH-1:0] pixel_b_in,
    input  wire                  pixel_vld_in,
    output wire                  ready,
    
    // Configurações Dinâmicas
    input  wire [MAG_WIDTH-1:0]  HIGH_THRESH,
    input  wire [MAG_WIDTH-1:0]  LOW_THRESH,
    input  wire [7:0]            gauss_peso,
    output wire [5:0]            gauss_addr,

    // Selecção Adaptativa de Parâmetros (APS)
    input  wire                  adaptive_en,   // 0 = limiares manuais (HIGH/LOW_THRESH), 1 = tabela adaptativa
    input  wire [1:0]            mdp,           // Ponto de operação desejado: 0=91%,1=92%,2=93%,3=94%
    input  wire [7:0]            noise_threshold, // Limiar de corrupção de píxel para o noise_estimator
    output wire [1:0]            kernel_sel_out,  // Selecção do kernel Gaussiano (para a ROM externa de pesos)

    // Interface de Saída
    output wire [7:0]            final_pixel_out,
    output wire                  final_vld_out
);

    // =========================================================================
    // 1. MÁQUINA DE ESTADOS (CONTROLE DE BACKPRESSURE)
    // =========================================================================
    localparam STATE_STREAM  = 1'b0;
    localparam STATE_PROCESS = 1'b1;
    
    reg  state, next_state;
    reg  start_gauss;
    wire win_7x7_vld;
    wire gauss_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= STATE_STREAM;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            STATE_STREAM: begin
                if (pixel_vld_in && win_7x7_vld) next_state = STATE_PROCESS;
            end
            STATE_PROCESS: begin
                if (gauss_done) next_state = STATE_STREAM;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            start_gauss <= 1'b0;
        else if (state == STATE_STREAM && next_state == STATE_PROCESS)
            start_gauss <= 1'b1;
        else
            start_gauss <= 1'b0;
    end

    assign ready = (state == STATE_STREAM);
    wire enable_7x7 = pixel_vld_in && (state == STATE_STREAM);

    // =========================================================================
    // 1.5 CONVERSÃO RGB -> ESCALA DE CINZA
    // =========================================================================
    wire [DATA_WIDTH-1:0] pixel_gray;

    rgb_gray_average inst_rgb_gray (
        .R(pixel_r_in),
        .G(pixel_g_in),
        .B(pixel_b_in),
        .gray_avg(pixel_gray)
    );

    // =========================================================================
    // 2. ETAPA 1: FILTRO GAUSSIANO (JANELA 7x7)
    // =========================================================================
    wire [(49*DATA_WIDTH)-1:0] window_7x7_flat;
    wire [DATA_WIDTH-1:0]      gauss_pixel_out;

    sliding_window_7x7_flex #(
        .WIDTH(IMG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) inst_window_7x7 (
        .clk(clk),
        .rst_n(rst_n),
        .kernel_size(2'b10),
        .pixel_vld(enable_7x7),
        .pixel_in(pixel_gray),
        .win_vld(win_7x7_vld),
        .window_data(window_7x7_flat)
    );
    
    gauss_smoothing_datapath inst_gauss (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_gauss),
        .done(gauss_done),
        .window_flat(window_7x7_flat),
        .peso_atual(gauss_peso),
        .contador_out(gauss_addr),
        .pixel_suavizado(gauss_pixel_out)
    );

    // =========================================================================
    // 2.1 SELEÇÃO ADAPTATIVA DE PARÂMETROS (APS)
    // =========================================================================
    // O estimador de ruído roda em paralelo ao Gauss sobre a mesma janela 7x7,
    // disparado pelo mesmo pulso de início (a janela fica congelada durante
    // STATE_PROCESS, então ambos os datapaths podem consumi-la simultaneamente).
    wire [3:0] noise_level;
    wire       noise_done;

    noise_estimator inst_noise_estimator (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_gauss),
        .window_flat(window_7x7_flat),
        .threshold(noise_threshold),
        .noise_level(noise_level),
        .done(noise_done)
    );

    // A tabela é uma ROM síncrona: o endereço {noise_level, mdp} só muda quando
    // noise_level é reescrito (uma vez por rodada), então th_high/th_low ficam
    // estáveis bem antes de serem consumidos pela histerese, várias dezenas de
    // ciclos depois.
    wire [1:0]  cfg_kernel_sel;
    wire [15:0] cfg_th_high, cfg_th_low; // Q0.16

    config_table inst_config_table (
        .clk(clk),
        .noise_level(noise_level),
        .mdp(mdp),
        .kernel_sel(cfg_kernel_sel),
        .th_high(cfg_th_high),
        .th_low(cfg_th_low)
    );

    // Conversão dos limiares de fração Q0.16 para o domínio de MAG_WIDTH bits
    // usado pela magnitude do gradiente (ver GRAD_MAG_FULL_SCALE acima).
    wire [15+MAG_WIDTH:0] prod_high = cfg_th_high * GRAD_MAG_FULL_SCALE;
    wire [15+MAG_WIDTH:0] prod_low  = cfg_th_low  * GRAD_MAG_FULL_SCALE;

    wire [MAG_WIDTH-1:0] adaptive_high_thresh = prod_high[15+MAG_WIDTH:16];
    wire [MAG_WIDTH-1:0] adaptive_low_thresh  = prod_low[15+MAG_WIDTH:16];

    wire [MAG_WIDTH-1:0] final_high_thresh = adaptive_en ? adaptive_high_thresh : HIGH_THRESH;
    wire [MAG_WIDTH-1:0] final_low_thresh  = adaptive_en ? adaptive_low_thresh  : LOW_THRESH;

    assign kernel_sel_out = adaptive_en ? cfg_kernel_sel : 2'b00;

    // =========================================================================
    // 3. ETAPA 2: GRADIENTE (SOBEL)
    // =========================================================================
    // A. Janela Deslizante 3x3 de 8 bits para alimentar o Sobel
    wire [7:0] g_w00, g_w01, g_w02, g_w10, g_w11, g_w12, g_w20, g_w21, g_w22;
    wire       g_win_vld;

    // gauss_done e gauss_pixel_out são atualizados na mesma borda de clock: gauss_done
    // sinaliza "válido" no mesmo ciclo em que pixel_suavizado ainda contém o valor da
    // rodada anterior. Atrasamos o valid em 1 ciclo para alinhar com o dado já escrito.
    reg gauss_done_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) gauss_done_d <= 1'b0;
        else        gauss_done_d <= gauss_done;
    end

    sliding_window_3x3 #(
        .WIDTH(IMG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) inst_win_grad (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(gauss_done_d),
        .pixel_in(gauss_pixel_out),
        
        .win00(g_w00), .win01(g_w01), .win02(g_w02),
        .win10(g_w10), .win11(g_w11), .win12(g_w12),
        .win20(g_w20), .win21(g_w21), .win22(g_w22),
        .win_vld(g_win_vld)
    );

    // B. Bloco Matemático do Gradiente
    wire [MAG_WIDTH-1:0] grad_mag;
    wire [1:0]           grad_dir;
    wire                 grad_vld;
    
    gradient_datapath gradient_datapath_inst (
        .clk(clk),
        .reset(~rst_n), // Invertido para respeitar a lógica ativa-alta
        .window_valid_in(g_win_vld),
        .p0(g_w00), .p1(g_w01), .p2(g_w02),
        .p3(g_w10), .p4(g_w11), .p5(g_w12),
        .p6(g_w20), .p7(g_w21), .p8(g_w22),
        
        .magnitude(grad_mag),
        .direction(grad_dir),
        .pixel_valid_out(grad_vld)
    );

    // =========================================================================
    // 4. ETAPA 3: NMS (SUPRESSÃO DE NÃO-MÁXIMOS)
    // =========================================================================
    // A. Janela Deslizante 3x3 de 14 bits (12 mag + 2 dir) para alimentar o NMS
    wire [13:0] nms_w00, nms_w01, nms_w02, nms_w10, nms_w11, nms_w12, nms_w20, nms_w21, nms_w22;
    wire        nms_win_vld;

    // WIDTH = IMG_WIDTH-2: o estágio anterior (janela do Sobel) já descarta 2
    // amostras por linha real (bordas col_count<2). Se esta janela contasse
    // "linha" a cada IMG_WIDTH pulsos recebidos, seu período de contagem
    // ficaria fora de fase com as linhas reais (o stream recebido só tem
    // IMG_WIDTH-2 pulsos por linha), causando deriva diagonal progressiva na
    // detecção de bordas de linha em linha.
    sliding_window_3x3 #(
        .WIDTH(IMG_WIDTH-2),
        .DATA_WIDTH(14)
    ) inst_win_nms (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_vld(grad_vld),
        .pixel_in({grad_dir, grad_mag}), // Concatenação do pacote de dados
        
        .win00(nms_w00), .win01(nms_w01), .win02(nms_w02),
        .win10(nms_w10), .win11(nms_w11), .win12(nms_w12),
        .win20(nms_w20), .win21(nms_w21), .win22(nms_w22),
        .win_vld(nms_win_vld)
    );

    // B. Bloco Lógico do NMS
    wire [MAG_WIDTH-1:0] nms_mag;
    wire                 nms_vld;
    
    nms_combinational #(
        .WIDTH(MAG_WIDTH)
    ) nms_combinational_inst (
        // Desempacotamento instantâneo [11:0] da magnitude
        .mag00(nms_w00[11:0]), .mag01(nms_w01[11:0]), .mag02(nms_w02[11:0]),
        .mag10(nms_w10[11:0]), .mag11(nms_w11[11:0]), .mag12(nms_w12[11:0]),
        .mag20(nms_w20[11:0]), .mag21(nms_w21[11:0]), .mag22(nms_w22[11:0]),
        // Desempacotamento instantâneo [13:12] da direção do píxel central (win11)
        .dir_center(nms_w11[13:12]),
        .win_vld_in(nms_win_vld),
        
        .nms_mag_out(nms_mag),
        .nms_vld_out(nms_vld)
    );

    // =========================================================================
    // 5. ETAPA FINAL: HISTERESE
    // =========================================================================
    // Nota: Este módulo já contém a sua própria sliding_window_3x3(DATA_WIDTH=2) internamente
    hysteresis_datapath #(
        .IMG_WIDTH(IMG_WIDTH),
        .MAG_WIDTH(MAG_WIDTH)
    ) inst_hysteresis (
        .clk(clk),
        .rst_n(rst_n),
        .nms_mag_in(nms_mag),
        .nms_vld_in(nms_vld),
        .HIGH_THRESH(final_high_thresh),
        .LOW_THRESH(final_low_thresh),
        
        .final_pixel_out(final_pixel_out),
        .final_vld_out(final_vld_out)
    );

endmodule