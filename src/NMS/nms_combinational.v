//`timescale 1ns / 1ps

module nms_combinational #(
    parameter WIDTH = 12 // Largura de bits da magnitude
)(
    // Entradas da janela 3x3 de magnitudes do nms_window_buffer
    input  wire [WIDTH-1:0] mag00, input  wire [WIDTH-1:0] mag01, input  wire [WIDTH-1:0] mag02,
    input  wire [WIDTH-1:0] mag10, input  wire [WIDTH-1:0] mag11, input  wire [WIDTH-1:0] mag12,
    input  wire [WIDTH-1:0] mag20, input  wire [WIDTH-1:0] mag21, input  wire [WIDTH-1:0] mag22,
    
    // Sinais de controle vindos do buffer
    input  wire [1:0]       dir_center,
    input  wire             win_vld_in,
    
    // Saídas para a próxima etapa (Duplo Limiar / Histerese)
    output wire [WIDTH-1:0] nms_mag_out,
    output wire             nms_vld_out
);

    // Fios internos para os vizinhos selecionados
    reg [WIDTH-1:0] vizinho1;
    reg [WIDTH-1:0] vizinho2;

    // =========================================================================
    // 1. MULTIPLEXADOR DE SELEÇÃO DE VIZINHOS
    // =========================================================================
    // A direção do gradiente (ortogonal à borda) dita quais vizinhos comparar.
    always @(*) begin
        case (dir_center)
            2'b00: begin 
                // 0 graus (Horizontal): Compara com o vizinho da Esquerda e da Direita
                vizinho1 = mag10;
                vizinho2 = mag12;
            end
            2'b01: begin 
                // 45 graus (Diagonal Ascendente /): Compara Canto Inf. Esq. e Canto Sup. Dir.
                vizinho1 = mag20;
                vizinho2 = mag02;
            end
            2'b10: begin 
                // 90 graus (Vertical): Compara com o vizinho de Cima e de Baixo
                vizinho1 = mag01;
                vizinho2 = mag21;
            end
            2'b11: begin 
                // 135 graus (Diagonal Descendente \): Compara Canto Sup. Esq. e Canto Inf. Dir.
                vizinho1 = mag00;
                vizinho2 = mag22;
            end
            default: begin
                vizinho1 = {WIDTH{1'b0}};
                vizinho2 = {WIDTH{1'b0}};
            end
        endcase
    end

    // =========================================================================
    // 2. COMPARADOR DE SUPRESSÃO E MÁSCARA DE SAÍDA
    // =========================================================================
    
    // Condição de sobrevivência: 
    // O centro deve ser maior ou igual a um vizinho, e estritamente maior que o outro.
    // Usamos >= de um lado e > do outro para evitar suprimir ambos num "planalto" liso.
    wire supressao_cond;
    assign supressao_cond = (mag11 >= vizinho1) && (mag11 > vizinho2);

    // Multiplexador de saída (Máscara): Se passou na condição, mantém o valor original mag11.
    // Se falhou (não é o máximo local), a magnitude é suprimida para zero.
    assign nms_mag_out = (supressao_cond) ? mag11 : {WIDTH{1'b0}};

    // =========================================================================
    // 3. PROPAGAÇÃO DO SINAL DE CONTROLE (HANDSHAKE)
    // =========================================================================
    
    // Como a lógica é puramente combinacional, o atraso é apenas elétrico (nanossegundos).
    // O sinal de validação passa reto pelo módulo para avisar a próxima etapa que 
    // a matemática deste ciclo deve ser registrada.
    assign nms_vld_out = win_vld_in;

endmodule