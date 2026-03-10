
module BB2
#(
    parameter FRAMES = 8,
    parameter SLICES = 8,
    parameter VN = 42,
    parameter LAYERS = 4,
    parameter LLR_W = 5
)
(
    input clk,
    input rst,

    // phase control
    input vn_phase,

    // clock gating enables
    input lvc_en,
    input cv_en,
    input qv_en,

    // addressing
    input [$clog2(FRAMES)-1:0] frame_id,
    input [$clog2(SLICES)-1:0] slice_id,
    input [$clog2(VN)-1:0] vn_id,
    input [$clog2(LAYERS)-1:0] layer_id,

    // from BB1
    input [LLR_W-1:0] lvc_in,
    input [LLR_W-1:0] cv_in,

    // channel LLR input
    input qv_load,
    input [LLR_W-1:0] qv_in,

    // outputs to BB1
    output reg [LLR_W-1:0] lvc_out,
    output reg [LLR_W-1:0] cv_out,
    output reg [LLR_W-1:0] qv_out
);

reg [LLR_W-1:0] Qv_mem
    [0:FRAMES-1][0:SLICES-1][0:VN-1];

reg [LLR_W-1:0] Lvc_mem
    [0:FRAMES-1][0:SLICES-1][0:VN-1][0:LAYERS-1];

reg [LLR_W-1:0] Cv_mem
    [0:FRAMES-1][0:SLICES-1][0:VN-1][0:LAYERS-1];

integer f,s,v,l;

always @(posedge clk)
begin
    if(rst)
    begin
        for(f=0;f<FRAMES;f=f+1)
        for(s=0;s<SLICES;s=s+1)
        for(v=0;v<VN;v=v+1)
        begin
            Qv_mem[f][s][v] <= 0;

            for(l=0;l<LAYERS;l=l+1)
            begin
                Lvc_mem[f][s][v][l] <= 0;
                Cv_mem[f][s][v][l]  <= 0;
            end
        end
    end
    else
    begin

        // Qv update only from IO
        if(vn_phase && qv_en)
            Qv_mem[frame_id][slice_id][vn_id] <= qv_in;

        // Lvc write from BB1
        if(vn_phase && lvc_en)
            Lvc_mem[frame_id][slice_id][vn_id][layer_id] <= lvc_in;

        // Cv write from BB1
        if(vn_phase && cv_en)
            Cv_mem[frame_id][slice_id][vn_id][layer_id] <= cv_in;

    end
end


always @(posedge clk)
begin
    qv_out  <= Qv_mem [frame_id][slice_id][vn_id];
    lvc_out <= Lvc_mem[frame_id][slice_id][vn_id][layer_id];
    cv_out  <= Cv_mem [frame_id][slice_id][vn_id][layer_id];
end

endmodule

