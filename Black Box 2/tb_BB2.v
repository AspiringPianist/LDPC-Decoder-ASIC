`timescale 1ns/1ps

module tb_BB2;

reg clk = 0;
always #20 clk = ~clk;

reg rst;

reg vn_phase;
reg lvc_en;
reg cv_en;
reg qv_en;

reg [2:0] frame_id;
reg [2:0] slice_id;
reg [5:0] vn_id;
reg [1:0] layer_id;

reg [4:0] lvc_in;
reg [4:0] cv_in;
reg [4:0] qv_in;

wire [4:0] lvc_out;
wire [4:0] cv_out;
wire [4:0] qv_out;

BB2 dut(
    .clk(clk),
    .rst(rst),
    .vn_phase(vn_phase),
    .lvc_en(lvc_en),
    .cv_en(cv_en),
    .qv_en(qv_en),
    .frame_id(frame_id),
    .slice_id(slice_id),
    .vn_id(vn_id),
    .layer_id(layer_id),
    .lvc_in(lvc_in),
    .cv_in(cv_in),
    .qv_in(qv_in),
    .lvc_out(lvc_out),
    .cv_out(cv_out),
    .qv_out(qv_out)
);

initial begin

/////////////////////////////////
// INITIALIZE EVERYTHING
/////////////////////////////////

rst = 1;

vn_phase = 0;

lvc_en = 0;
cv_en = 0;
qv_en = 0;

frame_id = 0;
slice_id = 0;
vn_id = 0;
layer_id = 0;

lvc_in = 0;
cv_in = 0;
qv_in = 0;

#100;
rst = 0;

/////////////////////////////////
// CN PHASE (NO WRITES)
/////////////////////////////////

vn_phase = 0;

lvc_en = 1;
cv_en = 1;

lvc_in = 5'h05;
cv_in  = 5'h07;

#200;

/////////////////////////////////
// VN PHASE WRITE LAYER 0
/////////////////////////////////

vn_phase = 1;

lvc_en = 1;
cv_en  = 1;

layer_id = 0;

lvc_in = 5'h0A;
cv_in  = 5'h0C;

#40;

lvc_en = 0;
cv_en  = 0;

#100;

/////////////////////////////////
// VN PHASE WRITE LAYER 1
/////////////////////////////////

lvc_en = 1;
cv_en  = 1;

layer_id = 1;

lvc_in = 5'h0F;
cv_in  = 5'h11;

#40;

lvc_en = 0;
cv_en  = 0;

#100;

/////////////////////////////////
// SLICE CHANGE WRITE
/////////////////////////////////

slice_id = 1;

lvc_en = 1;
cv_en  = 1;

lvc_in = 5'h14;
cv_in  = 5'h16;

#40;

lvc_en = 0;
cv_en  = 0;

#100;

/////////////////////////////////
// FRAME CHANGE WRITE
/////////////////////////////////

frame_id = 1;

lvc_en = 1;
cv_en  = 1;

lvc_in = 5'h18;
cv_in  = 5'h1A;

#40;

lvc_en = 0;
cv_en  = 0;

#100;

/////////////////////////////////
// Qv WRITE (during VN phase)
/////////////////////////////////

vn_phase = 1;
qv_en = 1;

qv_in = 5'h09;

#40;

qv_en = 0;

#200;

/////////////////////////////////
// Qv WRITE FOR NEXT FRAME
/////////////////////////////////

frame_id = 2;

vn_phase = 1;
qv_en = 1;

qv_in = 5'h12;

#40;

qv_en = 0;

#200;

$finish;

end

endmodule
