`ifndef __PANDA_MEMORY_H
`define __PANDA_MEMORY_H

class panda_memory #(
	int ADDR_WIDTH = 32,
	int DATA_WIDTH = 32
)extends uvm_object;
	
	typedef bit[ADDR_WIDTH-1:0] memory_address;
	typedef bit[DATA_WIDTH-1:0] memory_data;
	typedef bit[DATA_WIDTH/8-1:0] memory_strobe;
	
	protected logic[DATA_WIDTH-1:0] default_data;
	protected int byte_width;
	protected byte memory[memory_address];
	
	function new(string name = "panda_memory", int data_width = DATA_WIDTH);
		super.new(name);
		
		this.default_data = '0;
		this.byte_width = data_width / 8;
	endfunction
	
	virtual function void put(
		memory_data data, memory_strobe strobe, int byte_size,
		memory_address base, int word_index
	);
		memory_address start_address;
		memory_address now_addr;
		int byte_index;
		
		start_address = this.get_start_address(byte_size, base, word_index);
		
		for(int i = 0;i < byte_size;i++)
		begin
			now_addr = start_address + i;
			byte_index = now_addr % this.byte_width;
			
			if(strobe[byte_index])
				this.memory[now_addr] = data[8*byte_index+:8];
		end
	endfunction
	
	virtual function memory_data get(
		int byte_size, memory_address base, int word_index
	);
		memory_data data;
		memory_address start_address;
		memory_address now_addr;
		int byte_index;
		
		start_address = this.get_start_address(byte_size, base, word_index);
		
		data = {DATA_WIDTH{1'b0}};
		
		for(int i = 0;i < byte_size;i++)
		begin
			now_addr = start_address + i;
			byte_index = now_addr % this.byte_width;
			
			if(this.memory.exists(now_addr))
				data[8*byte_index+:8] = this.memory[now_addr];
			else
				data[8*byte_index+:8] = this.get_default_data(byte_index);
		end
		
		return data;
	endfunction
	
	virtual function bit exists(
		int byte_size, memory_address base, int word_index
	);
		memory_address start_address;
		memory_address now_addr;
		
		start_address = this.get_start_address(byte_size, base, word_index);
		
		for(int i = 0;i < byte_size;i++)
		begin
			now_addr = start_address + i;
			
			if(this.memory.exists(now_addr))
				return 1;
		end
		
		return 0;
	endfunction
	
	protected function memory_address get_start_address(
		int byte_size, memory_address base, int word_index
	);
		return (base & this.get_address_mask(byte_size)) + byte_size * word_index;
	endfunction
	
	protected function memory_address get_address_mask(int byte_size);
		memory_address mask;
		
		mask = byte_size - 1;
		mask = ~mask;
		
		return mask;
	endfunction
	
	protected function byte get_default_data(int byte_index);
		if($isunknown(this.default_data[8*byte_index+:8]))
			return $urandom_range(255);
		else
			return this.default_data[8*byte_index+:8];
	endfunction

endclass

typedef panda_memory #(.ADDR_WIDTH(`PANDA_ICB_MAX_ADDR_WIDTH), .DATA_WIDTH(`PANDA_ICB_MAX_DATA_WIDTH)) panda_icb_memory_base;

class panda_icb_memory extends tue_object_base #(
	.BASE(panda_icb_memory_base),
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(tue_status_dummy)
);
	
	virtual function void set_configuration(tue_configuration configuration);
		super.set_configuration(configuration);
		
		this.byte_width = this.configuration.data_width / 8;
	endfunction
	
	`tue_object_default_constructor(panda_icb_memory)
	`uvm_object_utils(panda_icb_memory)
	
endclass
	
`endif
