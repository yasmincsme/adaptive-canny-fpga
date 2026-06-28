`timescale 1ns / 1ps

module gauss_uc (
    input  wire clk,
    input  wire rst_n,          // Reset assíncrono (ativo em baixo)
    input  wire start,          // Inicia o processamento de um novo pixel
    input  wire limit_reached,  // Sinal do Comparador (count == window_size - 1)
    
    output reg  clr_acc,        // Zera o contador e os registradores CSA
    output reg  mac_en,         // Habilita a acumulação e incremento do contador
    output reg  write_en,       // Habilita a escrita no gaussian_reg
    output reg  done            // Sinaliza ao sistema que o pixel está pronto
);

    // Definição dos Estados (Codificação One-Hot ou Binária)
    localparam IDLE  = 2'b00;
    localparam MAC   = 2'b01;
    localparam WRITE = 2'b10;

    reg [1:0] state, next_state;

    // 1. Bloco Sequencial: Atualização do Estado
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 2. Bloco Combinacional: Lógica de Próximo Estado
    always @(*) begin
        // Valor padrão para evitar latches inferidos
        next_state = state; 
        
        case (state)
            IDLE: begin
                if (start) 
                    next_state = MAC;
            end
            
            MAC: begin
                // O comparador avisa quando processou todos os pixels (9, 25 ou 49)
                if (limit_reached) 
                    next_state = WRITE;
            end
            
            WRITE: begin
                // Volta para IDLE imediatamente após escrever o pixel final
                next_state = IDLE; 
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 3. Bloco Combinacional: Lógica de Saída (Máquina de Moore)
    always @(*) begin
        // Inicialização padrão segura
        clr_acc  = 1'b0;
        mac_en   = 1'b0;
        write_en = 1'b0;
        done     = 1'b0;

        case (state)
            IDLE: begin
                clr_acc = 1'b1; // Mantém a "sujeira" limpa antes de começar
            end
            
            MAC: begin
                mac_en = 1'b1;  // Deixa a matemática e o contador fluírem
            end
            
            WRITE: begin
                write_en = 1'b1; // Pulso de 1 ciclo para o gaussian_reg guardar o resultado
                done     = 1'b1; // Avisa a FSM superior (ou o Line Buffer) para avançar
            end
        endcase
    end

endmodule