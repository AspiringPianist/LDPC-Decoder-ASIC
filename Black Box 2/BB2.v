module BB2
#(
    parameter Z = 42,
    parameter FRAMES = 16,
    parameter LLR_W = 5
)
(
    input clk,
    input rst,

    // control from BB3
    input phase_cn,
    input [$clog2(Z*FRAMES)-1:0] addr,

    // channel LLR load
    input qv_load,
    input [LLR_W-1:0] qv_channel,

    // writes from BB1
    input lvc_we,
    input [LLR_W-1:0] lvc_in,

    input cv_we,
    input cv_in,

    // outputs to BB1
    output reg [LLR_W-1:0] qv_out,
    output reg [LLR_W-1:0] lvc_out,
    output reg cv_out
);

//////////////////////////////////////////////////////////////
// Column-Slice Local Memories
//////////////////////////////////////////////////////////////

reg [LLR_W-1:0] Qv_mem  [0:FRAMES*Z-1];   // Channel LLR
reg [LLR_W-1:0] Lvc_mem [0:FRAMES*Z-1];   // VN→CN messages
reg             Cv_mem  [0:FRAMES*Z-1];   // Hard decision

integer i;

//////////////////////////////////////////////////////////////
// Reset initialization
//////////////////////////////////////////////////////////////

always @(posedge clk)
begin
    if(rst)
    begin
        for(i=0;i<FRAMES*Z;i=i+1)
        begin
            Qv_mem[i]  <= 0;
            Lvc_mem[i] <= 0;
            Cv_mem[i]  <= 0;
        end
    end
    else
    begin

        //////////////////////////////////////////////////////
        // Channel LLR initialization
        //////////////////////////////////////////////////////

        if(qv_load)
            Qv_mem[addr] <= qv_channel;

        //////////////////////////////////////////////////////
        // VN update writes Lvc
        //////////////////////////////////////////////////////

        if(!phase_cn && lvc_we)
            Lvc_mem[addr] <= lvc_in;

        //////////////////////////////////////////////////////
        // CN decision writes Cv
        //////////////////////////////////////////////////////

        if(!phase_cn && cv_we)
            Cv_mem[addr] <= cv_in;

    end
end

//////////////////////////////////////////////////////////////
// Memory reads to BB1 compute fabric
//////////////////////////////////////////////////////////////

always @(posedge clk)
begin
    qv_out  <= Qv_mem[addr];
    lvc_out <= Lvc_mem[addr];
    cv_out  <= Cv_mem[addr];
end

endmodule
