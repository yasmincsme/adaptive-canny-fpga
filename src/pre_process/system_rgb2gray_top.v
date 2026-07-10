module system_rgb2gray_top (
    input  wire       clk_sys,       // Clock principal do sistema
    input  wire       rst_n,         // Reset assíncrono (ativo em baixo)
    
    // Interface de Configuração Estática do SPI
    input  wire       cpol,
    input  wire       cpha,
    input  wire       dord,
    
    // Interface Física SPI (Pinos)
    input  wire       sclk_in,
    input  wire       cs_n_in,
    input  wire       mosi_in,
    output wire       miso_out,
    
    // Interface de Controle e Monitoramento Externa
    input  wire       start,         // Sinal de início do frame
    output reg        pixel_vld,     // Pulso lógico indicando pixel processado e salvo
    
    // Interface de Leitura da RAM (Porta B)
    input  wire [17:0] read_addr_b,
    output wire [7:0]  read_data_b
);

    // -------------------------------------------------------------------------
    // Sinais Internos de Interconexão
    // -------------------------------------------------------------------------
    wire [7:0] spi_rx_data;
    wire       spi_rx_done;
    
    // Registradores PIPO para armazenamento temporário dos canais de cor
    reg [7:0] reg_R;
    reg [7:0] reg_G;
    reg [7:0] reg_B;
    
    // Saída do conversor
    wire [7:0] gray_data;
    
    // Sinais de controle da RAM (Porta A)
    reg         ram_we_a;
    reg [17:0]  ram_addr_a;
    
    // Flag de controle interno para permissão de processamento
    reg         processing_active;

    // -------------------------------------------------------------------------
    // Máquina de Estados Finita (FSM)
    // -------------------------------------------------------------------------
    reg [2:0] current_state, next_state;
    
    localparam STATE_IDLE      = 3'b000,
               STATE_WAIT_R    = 3'b001,
               STATE_WAIT_G    = 3'b010,
               STATE_WAIT_B    = 3'b011,
               STATE_CONVERT   = 3'b100,
               STATE_WRITE_RAM = 3'b101;

    // Lógica de Transição de Estados
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Lógica Combinacional de Próximo Estado e Sinais de Controle
    always @(*) begin
        next_state = current_state;
        ram_we_a   = 1'b1; // Inativo em nível alto (conforme dual_port_ram)
        pixel_vld  = 1'b0;
        
        case (current_state)
            STATE_IDLE: begin
                if (start) begin
                    next_state = STATE_WAIT_R;
                end
            end
            
            STATE_WAIT_R: begin
                if (!processing_active) begin
                    next_state = STATE_IDLE;
                end else if (spi_rx_done) begin
                    next_state = STATE_WAIT_G;
                end
            end
            
            STATE_WAIT_G: begin
                if (spi_rx_done) begin
                    next_state = STATE_WAIT_B;
                end
            end
            
            STATE_WAIT_B: begin
                if (spi_rx_done) begin
                    next_state = STATE_CONVERT;
                end
            end
            
            STATE_CONVERT: begin
                // Estado de retardo para garantir a estabilização do pipeline interno do rgb2gray
                next_state = STATE_WRITE_RAM;
            end
            
            STATE_WRITE_RAM: begin
                ram_we_a  = 1'b0; // Ativa a escrita na RAM (ativo em baixo)
                pixel_vld = 1'b1; // Sinaliza ao sistema que um pixel foi concluído
                next_state = STATE_WAIT_R;
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Lógica do Datapath (Registradores e Contadores)
    // -------------------------------------------------------------------------
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            processing_active <= 1'b0;
            ram_addr_a        <= 18'd0;
            reg_R             <= 8'd0;
            reg_G             <= 8'd0;
            reg_B             <= 8'd0;
        end else begin
            if (start) begin
                processing_active <= 1'b1;
                ram_addr_a        <= 18'd0; // Reinicia o ponteiro de escrita no início do frame
            end
            
            case (current_state)
                STATE_WAIT_R: begin
                    if (spi_rx_done) reg_R <= spi_rx_data;
                end
                
                STATE_WAIT_G: begin
                    if (spi_rx_done) reg_G <= spi_rx_data;
                end
                
                STATE_WAIT_B: begin
                    if (spi_rx_done) reg_B <= spi_rx_data;
                end
                
                STATE_WRITE_RAM: begin
                    // Incrementa o endereço após salvar o pixel atual
                    if (ram_addr_a == 18'd262143) begin
                        processing_active <= 1'b0; // Terminou o frame de 512x512
                    end else begin
                        ram_addr_a <= ram_addr_a + 1'b1;
                    end
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Instanciação dos Módulos Componentes
    // -------------------------------------------------------------------------
    
    // Instância do Escravo SPI
    spi_slave u_spi_slave (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(8'd0),            // Canal de transmissão não utilizado (miso fixo em IDLE/Z)
        .rx_data(spi_rx_data),
        .rx_done_flag(spi_rx_done),
        .cpol(cpol),
        .cpha(cpha),
        .dord(dord),
        .sclk_in(sclk_in),
        .cs_n_in(cs_n_in),
        .mosi_in(mosi_in),
        .miso_out(miso_out)
    );

    // Instância do Conversor RGB para Escala de Cinza
    rgb2gray u_rgb2gray (
        .clk(clk_sys),
        .R(reg_R),
        .G(reg_G),
        .B(reg_B),
        .gray(gray_data)
    );

    // Instância da RAM Dual Port (Barramento expandido para 18 bits)
    dual_port_ram u_dual_port_ram (
        .clk(clk_sys),
        .cs(1'b1),                 // Chip select permanentemente ativo
        
        // Porta A - Escrita do pipeline de conversão
        .we_a(ram_we_a),
        .addr_a(ram_addr_a),
        .data_in_a(gray_data),
        .data_out_a(),             // Saída de leitura da Porta A não utilizada
        
        // Porta B - Acesso de leitura externa (Leitura concorrente)
        .addr_b(read_addr_b),
        .data_out_b(read_data_b)
    );

endmodule