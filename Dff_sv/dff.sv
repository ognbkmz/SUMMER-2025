module dff (
    dff_if vif
);
always @(posedge vif.clk) begin
    if (vif.rst) begin
        vif.dout <= 1'b0; 
    end
    vif.dout <= vif.din; 
end
endmodule 
