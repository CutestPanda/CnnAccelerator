`ifndef __PANDA_CLK_RST_IF_H
`define __PANDA_CLK_RST_IF_H

interface panda_clock_if();
	bit started = 1'b0;
	realtime half_period = 0ns;
	bit clk = 1'b0;
	
	bit clk_p;
	bit clk_n;
	
	assign clk_p = clk;
	assign clk_n = ~clk;
	
	initial
	begin
		wait(started);
		
		forever
		begin
			# half_period clk <= started ? (~clk):1'b0;
		end
	end
	
	function automatic void start(realtime period_ns);
		set_period(period_ns);
		started = 1'b1;
	endfunction
	
	function automatic void set_period(realtime period_ns);
		half_period = period_ns / 2.0;
	endfunction
	
	function automatic void stop();
		half_period = 0ns;
		started = 1'b0;
	endfunction
	
	task automatic wait_cycles(int cycles);
		repeat(cycles)
			@(posedge clk);
	endtask
	
endinterface

interface panda_reset_if(input bit clk);
	bit reset = 1'b0;
	bit reset_n;
	
	assign reset_n = ~reset;
	
	task automatic initiate(
		realtime duration_ns,
		bit release_synchronous = 1'b0
	);
		reset = 1'b1;
		
		#(duration_ns);
		
		if(release_synchronous)
			@(posedge clk);
		
		reset = 1'b0;
	endtask
	
endinterface

`endif
