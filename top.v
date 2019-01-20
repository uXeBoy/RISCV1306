module top(
    input clk100,
    input [1:0] btn,
    output ftdi_rxd,
    input ftdi_txd,

    output [3:0] vga_r,  // VGA Red 4 bit
    output [3:0] vga_g,  // VGA Green 4 bit
    output [3:0] vga_b,  // VGA Blue 4 bit
    output       vga_hs, // H-sync pulse
    output       vga_vs  // V-sync pulse
);

wire clk_25mhz;
wire [8:0] din;
wire din_ready;

attosoc soc(
    .clk(clk_25mhz),
    .reset_n(btn[0]),
    .din(din),
    .din_ready(din_ready),
    .uart_tx(ftdi_rxd),
    .uart_rx(ftdi_txd)
);

SB_PLL40_PAD #(
    .FEEDBACK_PATH ("SIMPLE"),
    .DIVR (4'b0000),
    .DIVF (7'b0000111),
    .DIVQ (3'b101),
    .FILTER_RANGE (3'b101)
) uut (
    .RESETB         (1'b1),
    .BYPASS         (1'b0),
    .PACKAGEPIN     (clk100),
    .PLLOUTGLOBAL   (clk_25mhz)
);

parameter addr_width = 10;
parameter data_width = 8;
reg [data_width-1:0] mem [(1<<addr_width)-1:0];

reg  [data_width-1:0] dout;
wire [addr_width-1:0] raddr;
reg  [addr_width-1:0] raddr_r = 0;
reg  [addr_width-1:0] raddr_temp = 0;
assign raddr = raddr_r;

wire [addr_width-1:0] waddr;
reg  [addr_width-1:0] waddr_r = 0;
assign waddr = waddr_r;

always @(posedge din_ready) // Write memory
begin
  if (din[8]) begin
    waddr_r <= 0; // 'VSYNC'
  end
  else begin
    mem[waddr] <= din[7:0];
    waddr_r <= waddr_r + 1; // Increment address
  end
end

parameter h_pulse   = 96;   //H-SYNC pulse width 96 * 40 ns (25 Mhz) = 3.84 uS
parameter h_bp      = 48;   //H-BP back porch pulse width
parameter h_pixels  = 640;  //H-PIX Number of pixels horizontally
parameter h_fp      = 16;   //H-FP front porch pulse width
parameter h_pol     = 1'b0; //H-SYNC polarity
parameter h_frame   = 800;  //800 = 96 (H-SYNC) + 48 (H-BP) + 640 (H-PIX) + 16 (H-FP)
parameter v_pulse   = 2;    //V-SYNC pulse width
parameter v_bp      = 33;   //V-BP back porch pulse width
parameter v_pixels  = 480;  //V-PIX Number of pixels vertically
parameter v_fp      = 10;   //V-FP front porch pulse width
parameter v_pol     = 1'b1; //V-SYNC polarity
parameter v_frame   = 525;  //525 = 2 (V-SYNC) + 33 (V-BP) + 480 (V-PIX) + 10 (V-FP)

reg     [3:0]       vga_r_r;  //VGA colour registers R,G,B x 4 bit
reg     [3:0]       vga_g_r;
reg     [3:0]       vga_b_r;
reg                 vga_hs_r; //H-SYNC register
reg                 vga_vs_r; //V-SYNC register

assign  vga_r       = vga_r_r; //assign the output signals for VGA to the VGA registers
assign  vga_g       = vga_g_r;
assign  vga_b       = vga_b_r;
assign  vga_hs      = vga_hs_r;
assign  vga_vs      = vga_vs_r;

reg     [7:0]       timer_t = 8'b0; //8-bit timer with 0 initialization
reg                 reset = 1;
reg     [9:0]       c_row;      //visible frame register row
reg     [9:0]       c_col;      //visible frame register column
reg     [9:0]       c_hor;      //complete frame register horizontally
reg     [9:0]       c_ver;      //complete frame register vertically
reg     [9:0]       scale_col;  //counter for scaling horizontally

reg                 disp_en; //display enable flag
reg     [2:0]       bit_r;

always @ (posedge clk_25mhz)
begin
    dout <= mem[raddr]; // Read memory

    if(timer_t > 250) begin //generate 10 uS RESET signal
        reset <= 0;
    end
    else begin
        reset <= 1;              //while in reset display is disabled
        timer_t <= timer_t + 1;
        disp_en <= 0;
    end

    if(reset == 1) begin         //while RESET is high init counters
        c_hor <= 0;
        c_ver <= 0;
        vga_hs_r <= 1;
        vga_vs_r <= 0;
        c_row <= 0;
        c_col <= 0;
        scale_col <= 3;
    end
    else begin //update current beam position
        if(c_hor < h_frame - 1) begin
            c_hor <= c_hor + 1;
        end
        else begin
            //reset before the start of each line
            scale_col <= 3;
            //and set pixel buffer address back to beginning of line
            raddr_r <= raddr_temp;

            c_hor <= 0;
            if(c_ver < v_frame - 1) begin
                c_ver <= c_ver + 1;
            end
            else begin
                c_ver <= 0;
            end
        end
    end
    if(c_hor < h_pixels + h_fp + 1 || c_hor > h_pixels + h_fp + h_pulse) begin //H-SYNC generator
        vga_hs_r <= ~h_pol;
    end
    else begin
        vga_hs_r <= h_pol;
    end
    if(c_ver < v_pixels + v_fp || c_ver > v_pixels + v_fp + v_pulse) begin     //V-SYNC generator
        vga_vs_r <= ~v_pol;
    end
    else begin
        vga_vs_r <= v_pol;
    end
    if(c_hor < h_pixels) begin //c_col and c_row counters are updated only in the visible time-frame
        c_col <= c_hor;
    end
    if(c_ver < v_pixels) begin
        c_row <= c_ver;
    end
    if(c_hor < h_pixels && c_ver < v_pixels) begin //VGA colour signals are enabled only in the visible time frame
        disp_en <= 1;
    end
    else begin
        disp_en <= 0;
    end
    if(disp_en == 1 && reset == 0) begin

        if(c_col == 0 && c_row == 0) begin //pixel buffer address 0
          raddr_r <= 0;
          raddr_temp <= 0;
          bit_r <= 0;
        end

        if(c_row > 80 && c_row < 401) begin
            if(dout[bit_r]) begin //check pixel buffer data
              vga_r_r <= 15;
              vga_g_r <= 15;
              vga_b_r <= 15;
            end
            else begin
              vga_r_r <= 0;
              vga_g_r <= 0;
              vga_b_r <= 0;
            end

            if(c_col == scale_col) begin
              scale_col <= scale_col + 5;
              //and increment pixel buffer address horizontally
              raddr_r <= raddr_r + 1;
            end

            if(c_col == 639 && c_row == 84) begin
              raddr_temp <= 0;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 89) begin
              raddr_temp <= 0;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 94) begin
              raddr_temp <= 0;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 99) begin
              raddr_temp <= 0;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 104) begin
              raddr_temp <= 0;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 109) begin
              raddr_temp <= 0;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 114) begin
              raddr_temp <= 0;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 119) begin
              raddr_temp <= 128;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 124) begin
              raddr_temp <= 128;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 129) begin
              raddr_temp <= 128;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 134) begin
              raddr_temp <= 128;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 139) begin
              raddr_temp <= 128;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 144) begin
              raddr_temp <= 128;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 149) begin
              raddr_temp <= 128;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 154) begin
              raddr_temp <= 128;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 159) begin
              raddr_temp <= 256;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 164) begin
              raddr_temp <= 256;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 169) begin
              raddr_temp <= 256;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 174) begin
              raddr_temp <= 256;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 179) begin
              raddr_temp <= 256;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 184) begin
              raddr_temp <= 256;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 189) begin
              raddr_temp <= 256;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 194) begin
              raddr_temp <= 256;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 199) begin
              raddr_temp <= 384;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 204) begin
              raddr_temp <= 384;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 209) begin
              raddr_temp <= 384;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 214) begin
              raddr_temp <= 384;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 219) begin
              raddr_temp <= 384;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 224) begin
              raddr_temp <= 384;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 229) begin
              raddr_temp <= 384;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 234) begin
              raddr_temp <= 384;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 239) begin
              raddr_temp <= 512;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 244) begin
              raddr_temp <= 512;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 249) begin
              raddr_temp <= 512;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 254) begin
              raddr_temp <= 512;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 259) begin
              raddr_temp <= 512;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 264) begin
              raddr_temp <= 512;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 269) begin
              raddr_temp <= 512;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 274) begin
              raddr_temp <= 512;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 279) begin
              raddr_temp <= 640;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 284) begin
              raddr_temp <= 640;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 289) begin
              raddr_temp <= 640;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 294) begin
              raddr_temp <= 640;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 299) begin
              raddr_temp <= 640;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 304) begin
              raddr_temp <= 640;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 309) begin
              raddr_temp <= 640;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 314) begin
              raddr_temp <= 640;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 319) begin
              raddr_temp <= 768;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 324) begin
              raddr_temp <= 768;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 329) begin
              raddr_temp <= 768;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 334) begin
              raddr_temp <= 768;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 339) begin
              raddr_temp <= 768;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 344) begin
              raddr_temp <= 768;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 349) begin
              raddr_temp <= 768;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 354) begin
              raddr_temp <= 768;
              bit_r <= 7;
            end

            if(c_col == 639 && c_row == 359) begin
              raddr_temp <= 896;
              bit_r <= 0;
            end
            if(c_col == 639 && c_row == 364) begin
              raddr_temp <= 896;
              bit_r <= 1;
            end
            if(c_col == 639 && c_row == 369) begin
              raddr_temp <= 896;
              bit_r <= 2;
            end
            if(c_col == 639 && c_row == 374) begin
              raddr_temp <= 896;
              bit_r <= 3;
            end
            if(c_col == 639 && c_row == 379) begin
              raddr_temp <= 896;
              bit_r <= 4;
            end
            if(c_col == 639 && c_row == 384) begin
              raddr_temp <= 896;
              bit_r <= 5;
            end
            if(c_col == 639 && c_row == 389) begin
              raddr_temp <= 896;
              bit_r <= 6;
            end
            if(c_col == 639 && c_row == 394) begin
              raddr_temp <= 896;
              bit_r <= 7;
            end

        end
        else begin //everything else is black
            vga_r_r <= 0;
            vga_g_r <= 0;
            vga_b_r <= 0;
        end
    end
    else begin //when display is not enabled everything is black
        vga_r_r <= 0;
        vga_g_r <= 0;
        vga_b_r <= 0;
    end

end

endmodule
