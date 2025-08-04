interface dff_if;
    logic clk;
    logic rst;
    logic din,dout;
endinterface

class transaction;
    rand bit din;
    bit dout;

    function void display(input string tag);
        $display("[%0s]: Din : %0d || Dout : %0d",tag,din,dout);
    endfunction
     
    function transaction copy();
        copy=new();
        copy.din = this.din;
        copy.dout = this.dout;
    endfunction

endclass


class generator;
    transaction trans;
    mailbox #(transaction) mbx;//   -> driver 
    mailbox #(transaction) mbref;// -> scoreboard
    event   nextsco;
    event   done;
    int     count;

    function new(mailbox #(transaction) mbx,mailbox #(transaction) mbref);
        this.mbx = mbx;
        this.mbref = mbref;
        trans = new();
    endfunction

    task run();
        repeat(count)begin
            assert(trans.randomize())else $error("[GEN]: RANDOMIZATION FAILED");
            mbx.put(trans.copy());
            mbref.put(trans.copy());
            trans.display("GEN");
            @(nextsco);
        end
        ->done;
    endtask
endclass

class driver;
    transaction data;
    mailbox #(transaction) mbx;
    virtual dff_if vif;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task reset();
        vif.rst <=1'b1;
        repeat(5)@(posedge vif.clk);
        vif.rst <=1'b0;
        @(posedge vif.clk);
        $display("[DRV]: Reset is Done");
    endtask

    task run();
        xforever begin
          	mbx.get(data);
            vif.din <= data.din;
            @(posedge vif.clk);
            data.display("DRV");
            vif.din <= 1'b0;
            @(posedge vif.clk);
        end
    endtask
endclass

class monitor;
    transaction trans;
    virtual dff_if vif;
    mailbox #(transaction) mbx;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task run();
        trans = new();
        forever begin
            repeat(2)@(posedge vif.clk);
            trans.dout = vif.dout;
            mbx.put(trans);
            trans.display("MON");
        end
    endtask
endclass


class scoreboard;
    transaction tr;
    transaction tref;
    mailbox #(transaction) mbx;
    mailbox #(transaction) mbref;
    
    event nextsco;

    function new(mailbox #(transaction) mbx,mailbox #(transaction) mbref);
        this.mbx=mbx;
        this.mbref=mbref;
    endfunction

    task run();
        forever begin
            mbx.get(tr);
            mbref.get(tref);
            tr.display("SCO");
            tref.display("REF");
            if(tr.dout == tref.din)
                $display("DATA MATCHED");
            else
                $display("DATA MISMATCHED");
            $display("--------------------------------------");
            ->nextsco;
        end
    endtask

endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;
    event next;
    mailbox #(transaction) mbx;//gen->driver
    mailbox #(transaction) mby;//monitor->scoreboard
    mailbox #(transaction) mbref;//gen->scoreboard

    virtual dff_if vif;
    function new(virtual dff_if vif);
        mbx = new();//gen->driver
        mby = new();//monitor->scoreboard
        mbref = new();//gen->scoreboard
        gen = new(mbx,mbref);
        drv = new(mbx);
        mon = new(mby);
        sco = new(mby,mbref);
        this.vif = vif;
        drv.vif = this.vif;
        mon.vif = this.vif;
        gen.nextsco = next;
        sco.nextsco = next;
    endfunction

    task pre_test;
        drv.reset();
    endtask

    task test;
        fork
            drv.run();
            gen.run();
            mon.run();
            sco.run();
        join_any
    endtask

    task post_test;
        wait(gen.done.triggered);
        $finish();
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass


module tb;
  	dff_if vif();
    dff dut(vif);
    
    initial begin
        vif.clk <= 0;
    end

    always #5 vif.clk <= ~vif.clk;

    environment env;

    initial begin
        env = new(vif);
        env.gen.count  = 30;
        env.run();
    end
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule
