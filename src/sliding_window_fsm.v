//`timescale 1ns / 1ps

module sliding_window_fsm #(
    parameter WIDTH = 512         // Largura da imagem em pixels
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pixel_vld,   // Stream de pixel ativo vindo de fora
    input  wire [1:0]  kernel_size, // 00=3x3, 01=5x5, 10=7x7
    input  wire [31:0] pixel_count, // Valor atual do contador vindo da janela
    
    output reg         count_en,    // Habilita o incremento do contador na janela
    output reg         win_vld      // Validação global da vizinhança 7x7
);

    // =========================================================================
    // 1. DEFINIÇÃO DOS ESTADOS DA FSM (Codificação Gray/One-Hot implícita)
    // =========================================================================
    localparam [1:0] ST_IDLE       = 2'b00,
                     ST_FILLING    = 2'b01,
                     ST_PROCESSING = 2'b10;

    reg [1:0] current_state, next_state;
    reg [31:0] threshold;

    // =========================================================================
    // 2. CÁLCULO COMBINACIONAL DO THRESHOLD (LIMITE)
    // =========================================================================
    // Determina quantos pixels precisam ser armazenados antes do primeiro cálculo
    always @(*) begin
        case (kernel_size)
            2'b00:   threshold = (WIDTH * 2) + 3; // 3x3: 2 linhas cheias + 3 pixels
            2'b01:   threshold = (WIDTH * 4) + 5; // 5x5: 4 linhas cheias + 5 pixels
            2'b10:   threshold = (WIDTH * 6) + 7; // 7x7: 6 linhas cheias + 7 pixels
            default: threshold = (WIDTH * 2) + 3;
        endcase
    end

    // =========================================================================
    // 3. REGISTRADOR DE ESTADO (BLOCO SÍNCRONO)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // 4. LÓGICA DE TRANSIÇÃO E SAÍDAS (BLOCO COMBINACIONAL)
    // =========================================================================
    always @(*) begin
        // Valores default para evitar a inferência de Latches indesejados
        next_state = current_state;
        count_en   = 1'b0;
        win_vld    = 1'b0;

        case (current_state)
            
            // -----------------------------------------------------------------
            ST_IDLE: begin
                count_en = 1'b0;
                win_vld  = 1'b0;
                // Se houver um pixel válido na entrada, começa o preenchimento
                if (pixel_vld) begin
                    next_state = ST_FILLING;
                end
            end

            // -----------------------------------------------------------------
            ST_FILLING: begin
                // Enquanto estiver preenchendo, o contador na janela deve acumular
                count_en = 1'b1; 
                win_vld  = 1'b0; // Saída ainda inválida

                // Checa se o contador atingiu o limite necessário para o operador atual
                // Subtraímos 1 porque o sinal de controle dita o próximo ciclo do hardware
                if (pixel_vld && (pixel_count >= threshold - 1)) begin
                    next_state = ST_PROCESSING;
                end
            end

            // -----------------------------------------------------------------
            ST_PROCESSING: begin
                count_en = 1'b0; // Matriz já está cheia, não precisa mais contar no FILLING
                
                // O bloco matemático só pode operar se o pixel atual for legítimo.
                // Isso congela o pipeline automaticamente caso o fluxo externo pause.
                win_vld  = pixel_vld; 

                // Se o fluxo parar permanentemente ou se você quiser resetar por frame,
                // uma condição de "Fim de Imagem" poderia fazer a FSM voltar para ST_IDLE aqui.
                if (!pixel_vld) begin
                    // Opcional: dependendo da sua arquitetura, você pode manter em PROCESSING
                    // ou voltar para IDLE para reiniciar um novo frame. Mantemos aqui por simplicidade.
                    next_state = ST_PROCESSING; 
                end
            end

            // -----------------------------------------------------------------
            default: begin
                next_state = ST_IDLE;
            end

        endcase
    end

endmodule