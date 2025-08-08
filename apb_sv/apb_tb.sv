interface abp_if;
  logic pclk;
  logic prstn;
  logic psel;
  logic penable;
  logic pwrite;
  logic [31:0] paddr;
  logic [7:0] pwdata;
  logic pready;
  logic pslverr;
  logic [7:0] prdata;
endinterface

class transaction;
  rand bit [31:0] paddr,
  rand bit [7:0] pwdata,
  rand bit pwrite,
  
  rand bit psel;
  rand bit penable,

  bit pready,
  bit pslverr,
  bit [7:0] prdata

  constraint addr_c {
    paddr >= 0;
    paddr <= 15;
  }

  constraint data_c {
    pwdata >= 0;
    pwdata <= (1<<8)-1;
  }

  task display (input string tag);
    $display("[%s] paddr:%2d  pwdata:%3d    pwrite:%b   prdata:%3d   pslverr:%3b   ", tag,paddr,pwdata,pwrite,prdata,pslverr);
  endtask
endclass


class generator;
  transaction tr;
  mailbox #(transaction) mbx;
  int count =0;

  event nextdrv;
  event nextsco;
  event done;

  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
  endfunction
  
  task run();
    repeat (count)
    begin
      assert (tr.randomize) else   $display("randomization failed");
      mbx.put(tr);
      tr.display(GEN);
      @(nextdrv);
      @(nextsco);
    end
    ->done;
  endtask
endclass

class driver;
  vitrual abp_if vif;
  transaction tr;
  mailbox #(transaction) mbx;
  event nextdrv;


  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  task  reset();
    vif.prstn <= 1'b0;
    vif.psel <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwdata <= 0;
    vif.paddr <= 0;
    vif.pwrite <= 1'b0;
    repeat(5)@(posedge vif.pclk);
    vif.prstn <= 1'b0;
    $display("[DRV]: RESET DONE");
    $display("--------------------------------------------------------")
  endtask 

  task  run();
    forever begin
        mbx.get(tr);
        @(posedge vif.pclk);
        vif.psel    <= 1'b1;
        vif.penable <= 1'b0;
        vif.pwrite  <= tr.pwrite;
        @(posedge vif.pclk);
        vif.penable <= 1'b1;
        vif.paddr   <= tr.paddr;
        vif.pwdata  <= tr.pwdata;
        @(posedge vif.pclk);
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        tr.display ("DRV");
      ->nextdrv;    
    end
  endtask   
endclass

class monitor;
  virtual abp_if vif;
  mailbox #(transaction) mbx;
  transaction tr;

  function new();
    this.mbx = mbx;
    tr = new();
  endfunction

  task run();
    forever begin
        @(posedge vif.pclk);
        if(vif.pready)
        begin
          tr.pwdata  = vif.pwdata;
          tr.paddr   = vif.paddr;
          tr.pwrite  = vif.pwrite;
          tr.prdata  = vif.prdata;
          tr.pslverr  = vif.pslverr;
          @(posedge vif.pclk);
          tr.display("MON");
          mbx.put(tr);
        end
    end

  endtask
endclass

class scoreboard;
  mailbox #(transaction) mbx;
  transaction tr;
  event nextsco;
  bit [7:0] pwdata [16] = '{default: 0};
  bit [7:0] rdata;
  int errcount = 0;

  function new(mailbox #(transaction) mbx);
    this.mbx =mbx;
  endfunction


  task run();
    forever begin
      mgx.get(tr);
      tr.display("SCO");
      if(tr.pwrite&& !tr.pslverr)begin
        pwdata[tr.paddr] = tr.pwdata;
        $display("[SCO] : DATA STORED DATA : %0d ADDR: %0d",tr.pwdata, tr.paddr);
      end
      else if (!tr.pwrite&& !tr.pslverr)begin
        rdata = pwdata[tr.paddr];
        if (tr.prdata == rdata)begin
          $display("[SCO] : Data Matched");           
        end       else
          begin
          errcount++;
          $display("[SCO] : Data Mismatched");
          end 
      end
      else if(pslverr)
       begin
          $display("[SCO] : SLV ERROR DETECTED");
        end
      $display("---------------------------------------------------------------------------------------------------");
      ->nextsco; 
    end
  endtask
endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco; 
    
    event nextgd; ///gen -> drv
    event nextgs;  /// gen -> sco

    mailbox #(transaction) gdmbx; ///gen - drv

    mailbox #(transaction) msmbx;  /// mon - sco
    
    virtual abp_if vif;

    function new(virtual abp_if vif);
      gdmbx = new();
      msmbx = new();

      gen=new(gdmbx);
      drv=new(gdmbx);
      mon=new(msbx);
      sco=new(msbx);

      this.vif = vif;
      drv.vif =this.vif;
      mon.vif =this.vif;

      gen.nextdrv = nextgd;      
      drv.nextdrv = nextgd;      
            
      gen.nextdrv = nextgs;
      sco.nextdrv = nextgs;
    endfunction

    task pre_test();
      drv.reset();
    endtask
task test();
  fork
    gen.run();
    drv.run();
    mon.run();
    sco.run();
  join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);  
    $display("----Total number of Mismatch : %0d------",sco.err);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();  
  endtask
  
  
  
endclass
 
 
//////////////////////////////////////////////////
 module tb;
    
   abp_if vif();
 
   
   apb_s dut (
   vif.pclk,
   vif.prsttn,
   vif.paddr,
   vif.psel,
   vif.penable,
   vif.pwdata,
   vif.pwrite,
   vif.prdata,
   vif.pready,
   vif.pslverr
   );
   
    initial begin
      vif.pclk <= 0;
    end
    
    always #10 vif.pclk <= ~vif.pclk;
    
    environment env;
    
    
    
    initial begin
      env = new(vif);
      env.gen.count = 20;
      env.run();
    end
      
    
    initial begin
      $dumpfile("dump.vcd");
      $dumpvars;
    end       
  endmodule