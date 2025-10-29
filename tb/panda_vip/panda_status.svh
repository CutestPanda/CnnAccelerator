`ifndef __PANDA_STATUS_H
`define __PANDA_STATUS_H

class panda_icb_status extends tue_status;
	
	panda_icb_memory memory;
	
	function new(string name = "panda_icb_status");
		super.new(name);
		
		this.memory = panda_icb_memory::type_id::create("memory");
	endfunction
	
	`uvm_object_utils(panda_icb_status)
	
endclass

`endif
