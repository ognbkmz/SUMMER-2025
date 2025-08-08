
module apb_slave(
  input pclk,
  input prstn,
  input psel,
  input penable,
  input pwrite,
  input [31:0] paddr,
  input [7:0] pwdata,

  output reg pready,
  output reg pslverr,
  output [7:0] prdata

);

typedef enum bit [1:0] {
  idle,
  write,
  read
}state;
reg [7:0] mem [16];

reg [1:0] state,nstate;

bit addv_err,data_err;

always @(posedge pclk , negedge prstn) begin
  if(!prstn)
    state <= idle;
  else
    state <= nstate;
end

always_comb begin
  case (state)
    idle:begin
      prdata = 8'h00;      
      pready = 1'b0;      
      if (psel && pwrite)//write
        nstate = write;
      else if (psel && !pwrite)//read
        nstate = read;
      else
        nstate = idle;
    end 
    write:
    begin
      if (penable && psel) 
      begin
        if (!addr_err && !addv_err && !data_err) 
        begin
          pready = 1'b1;
          mem[paddr] = pwdata;
          nstate  = idle;
        end
        else 
        begin
          pread = 1'b1;
          nstate = idle;
        end
      end
    end
    read:begin
      if (penable && psel) 
      begin
        if (!addr_err && !addv_err && !data_err) 
        begin
          pready = 1'b1;
          prdata = mem[paddr];
          nstate  = idle;
        end
        else 
        begin
          pready = 1'b1;
          prdata = 8'h00;
          nstate = idle;
        end
      end
    end
    default:
          prdata = 8'h00;
          pready = 1'b0;
          nstate = idle;
  endcase
end
reg av_t =0;
always_comb
begin
  if (paddr>=0 && paddr<16)
    av_t =1'b0;
  else 
    av_t =1'b1;
end

reg dv_t =0;
always_comb
begin
  if (pwdata>=0 && pwdata<((1<<8)-1))
    dv_t =1'b0;
  else 
    dv_t =1'b1;
end

assign addv_err = (nstate== write || read) ? av_t : 1'b0; 
assign data_err = (nstate== write || read) ? dv_t : 1'b0;

assign pslverr = (psel && penable) ? (addv_err || data_err): 1'b0;

endmodule 