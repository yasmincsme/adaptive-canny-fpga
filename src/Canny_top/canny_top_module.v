`timescale 1ns / 1ps

module canny_top_module #(
    parameter IMG_WIDTH   = 512,
    parameter DATA_WIDTH  = 8,
    parameter MAG_WIDTH   = 12
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Interface de Entrada de Vídeo
    input  wire [DATA_WIDTH-1:0] pixel_in,
    input  wire                  pixel_vld_in,
    output wire                  ready,
    
    // Configurações Dinâmicas
    input  wire [MAG_WIDTH-1:0]  HIGH_THRESH,
    input  wire [MAG_WIDTH-1:0]  LOW_THRESH,
    input  wire [7:0]            gauss_peso,
    output wire [5:0]            gauss_addr,
    
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
        .pixel_in(pixel_in),
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

    sliding_window_3x3 #(
        .WIDTH(IMG_WIDTH),
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
        .HIGH_THRESH(HIGH_THRESH),
        .LOW_THRESH(LOW_THRESH),
        
        .final_pixel_out(final_pixel_out),
        .final_vld_out(final_vld_out)
    );

endmodule