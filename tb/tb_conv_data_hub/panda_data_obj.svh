`ifndef __PANDA_DATA_OBJ_H
`define __PANDA_DATA_OBJ_H

virtual class DataBlk extends uvm_object;
	
	protected DataBlk data_blks[];
	protected int unsigned baseaddr;
	protected int unsigned bytes_n;
	
	static function uint_queue get_uint_queue_in_range(int a, int b);
		uint_queue q;
		
		for(int i = a;i <= b;i++)
			q.push_back(uint'(i));
		
		return q;
	endfunction
	
	function void set_baseaddr(int unsigned baseaddr);
		this.baseaddr = baseaddr;
	endfunction
	
	function int unsigned get_baseaddr();
		return this.baseaddr;
	endfunction
	
	function int unsigned get_len_in_byte();
		return this.bytes_n;
	endfunction
	
	virtual function uint_queue get_available_index();
		return DataBlk::get_uint_queue_in_range(0, this.data_blks.size() - 1);
	endfunction
	
	virtual function DataBlk get_sub_data_blk(int unsigned index);
		if(index < this.data_blks.size())
			return this.data_blks[index];
		else
			return null;
	endfunction
	
	virtual function int unsigned num_of_sub_data_blk();
		return this.data_blks.size();
	endfunction
	
	virtual function logic[7:0] get_byte_by_addr(int unsigned ofs_addr);
		foreach(this.data_blks[i])
		begin
			int unsigned blk_baseaddr;
			
			blk_baseaddr = this.data_blks[i].get_baseaddr();
			
			if(
				(ofs_addr >= blk_baseaddr) && 
				(ofs_addr < (blk_baseaddr + this.data_blks[i].get_len_in_byte()))
			)
				return this.data_blks[i].get_byte_by_addr(ofs_addr - blk_baseaddr);
		end
		
		return 8'hxx;
	endfunction
	
	protected function bit set_blk(int unsigned index, DataBlk blk);
		if(index >= this.data_blks.size())
			return 1'b0;
		else
		begin
			this.data_blks[index] = blk;
			
			return 1'b1;
		end
	endfunction
	
	protected function bit finish_adding_blk();
		int unsigned total_len;
		
		total_len = 0;
		
		foreach(this.data_blks[i])
		begin
			if(this.data_blks[i] != null)
			begin
				this.data_blks[i].set_baseaddr(total_len);
				
				total_len += this.data_blks[i].get_len_in_byte();
			end
			else
				return 1'b0;
		end
		
		this.bytes_n = total_len;
		
		return 1'b1;
	endfunction
	
	`tue_object_default_constructor(DataBlk)
	
endclass

class Surface extends tue_object_base #(
	.BASE(DataBlk),
	.CONFIGURATION(SurfaceCfg),
	.STATUS(tue_status_dummy)
);
	
	protected bit[15:0] data[];
	
	function bit set_pt(int unsigned index, bit[15:0] val);
		if(index >= this.data.size())
			return 1'b0;
		else
		begin
			this.data[index] = val;
			
			return 1'b1;
		end
	endfunction
	
	function logic[15:0] get_pt_by_index(int unsigned index);
		if(index >= this.data.size())
			return 16'hxxxx;
		else
			return this.data[index];
	endfunction
	
	function int unsigned get_size();
		return this.data.size();
	endfunction
	
	virtual function logic[7:0] get_byte_by_addr(int unsigned ofs_addr);
		if(ofs_addr >= this.get_len_in_byte())
			return 8'hxx;
		else
		begin
			if(this.configuration.is_format_16)
				return ofs_addr[0] ? this.data[ofs_addr/2][15:8]:this.data[ofs_addr/2][7:0];
			else
				return this.data[ofs_addr][7:0];
		end
	endfunction
	
	virtual function void set_configuration(tue_configuration configuration);
		super.set_configuration(configuration);
		
		this.data = new[this.configuration.len_foreach_sfc];
		this.bytes_n = this.configuration.len_foreach_sfc * (this.configuration.is_format_16 ? 2:1);
	endfunction
	
	`tue_object_default_constructor(Surface)
	
	`uvm_object_utils_begin(Surface)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(data, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	
endclass

typedef Surface FmapSfc;
typedef Surface KernalSfc;

virtual class SurfaceGrpBase #(
	type SfcType = Surface
)extends tue_object_base #(
	.BASE(DataBlk),
	.CONFIGURATION(SurfaceGrpCfg),
	.STATUS(tue_status_dummy)
);
	
	virtual function bit set_sfc(int unsigned index, SfcType sfc);
		return this.set_blk(index, sfc);
	endfunction
	
	virtual function bit finish_adding_sfc();
		return this.finish_adding_blk();
	endfunction
	
	virtual function void set_configuration(tue_configuration configuration);
		super.set_configuration(configuration);
		
		this.data_blks = new[this.configuration.sfc_n];
	endfunction
	
	`tue_object_default_constructor(SurfaceGrpBase)
	
endclass

class FmapRow extends SurfaceGrpBase #(
	.SfcType(FmapSfc)
);
	
	`tue_object_default_constructor(FmapRow)
	
	`uvm_object_utils_begin(FmapRow)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_object(data_blks, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class KernalWgtBlk extends SurfaceGrpBase #(
	.SfcType(KernalSfc)
);
	
	`tue_object_default_constructor(KernalWgtBlk)
	
	`uvm_object_utils_begin(KernalWgtBlk)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_object(data_blks, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class SurfaceSetBase extends tue_object_base #(
	.BASE(DataBlk),
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	protected DataBlk sfc_table[int unsigned];
	
	local int unsigned keys_fifo[$];
	
	virtual function void put_sfc(int unsigned key, DataBlk e);
		this.sfc_table[key] = e;
	endfunction
	
	virtual function void finish_adding_sfc();
		int unsigned key;
		int unsigned max_addr;
		
		max_addr = 0;
		
		if(this.sfc_table.first(key))
		begin
			do
			begin
				this.keys_fifo.push_back(key);
				
				if((this.sfc_table[key].get_baseaddr() + this.sfc_table[key].get_len_in_byte()) > max_addr)
					max_addr = this.sfc_table[key].get_baseaddr() + this.sfc_table[key].get_len_in_byte();
			end
			while(this.sfc_table.next(key));
		end
		
		this.bytes_n = max_addr;
	endfunction
	
	virtual function uint_queue get_available_index();
		return this.keys_fifo;
	endfunction
	
	virtual function DataBlk get_sub_data_blk(int unsigned index);
		if(this.sfc_table.exists(index))
			return this.sfc_table[index];
		else
			return null;
	endfunction
	
	virtual function int unsigned num_of_sub_data_blk();
		return this.keys_fifo.size();
	endfunction
	
	virtual function logic[7:0] get_byte_by_addr(int unsigned ofs_addr);
		int unsigned key;
		
		foreach(this.keys_fifo[i])
		begin
			DataBlk blk;
			int unsigned baseaddr;
			
			key = this.keys_fifo[i];
			
			blk = this.sfc_table[key];
			baseaddr = blk.get_baseaddr();
			
			if(
				(ofs_addr >= baseaddr) && 
				(ofs_addr < (baseaddr + blk.get_len_in_byte()))
			)
				return blk.get_byte_by_addr(ofs_addr - baseaddr);
		end
		
		return 8'hxx;
	endfunction
	
	`tue_object_default_constructor(SurfaceSetBase)
	
endclass

class Fmap extends SurfaceSetBase;
	
	function void put_fmap_row(int unsigned actual_rid, FmapRow fmap_row);
		this.put_sfc(actual_rid, fmap_row);
	endfunction
	
	function void finish_adding_fmap_row();
		this.finish_adding_sfc();
	endfunction
	
	`tue_object_default_constructor(Fmap)
	
	`uvm_object_utils_begin(Fmap)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_aa_object_int(sfc_table, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class KernalCGrp extends tue_object_base #(
	.BASE(DataBlk),
	.CONFIGURATION(KernalCGrpCfg),
	.STATUS(tue_status_dummy)
);
	
	virtual function bit set_wgt_blk(int unsigned index, KernalWgtBlk wgt_blk);
		return this.set_blk(index, wgt_blk);
	endfunction
	
	virtual function bit finish_adding_wgt_blk();
		return this.finish_adding_blk();
	endfunction
	
	virtual function void set_configuration(tue_configuration configuration);
		super.set_configuration(configuration);
		
		case(this.configuration.kernal_shape)
			KBUFGRPSZ_1x1: this.data_blks = new[1 * 1];
			KBUFGRPSZ_3x3: this.data_blks = new[3 * 3];
			KBUFGRPSZ_5x5: this.data_blks = new[5 * 5];
			KBUFGRPSZ_7x7: this.data_blks = new[7 * 7];
			KBUFGRPSZ_9x9: this.data_blks = new[9 * 9];
			KBUFGRPSZ_11x11: this.data_blks = new[11 * 11];
		endcase
	endfunction
	
	function int unsigned get_size();
		return this.data_blks.size();
	endfunction
	
	`tue_object_default_constructor(KernalCGrp)
	
	`uvm_object_utils_begin(KernalCGrp)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_object(data_blks, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class KernalSet extends SurfaceSetBase;
	
	function void put_kernal_cgrp(int unsigned actual_cgrpid, KernalCGrp kernal_cgrp);
		this.put_sfc(actual_cgrpid, kernal_cgrp);
	endfunction
	
	function void finish_adding_kernal_cgrp();
		this.finish_adding_sfc();
	endfunction
	
	`tue_object_default_constructor(KernalSet)
	
	`uvm_object_utils_begin(KernalSet)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(bytes_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_aa_object_int(sfc_table, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class FmapBuilder extends uvm_object;
	
	local Fmap feature_map;
	
	function new(string name = "FmapBuilder");
		super.new(name);
		
		this.feature_map = Fmap::type_id::create();
	endfunction
	
	function void build_default_feature_map(const ref ConvDataHubCfg cfg);
		for(int unsigned i = 0;i < cfg.total_fmrow_n;i++)
		begin
			FmapRow row;
			FmapRowCfg row_cfg;
			SurfaceCfg sfc_cfg;
			
			row = FmapRow::type_id::create();
			
			row_cfg = FmapRowCfg::type_id::create();
			if(!row_cfg.randomize() with{
				sfc_n == cfg.fmrow_len;
				len_foreach_sfc == cfg.sfc_data_n_foreach_fmrow[i];
			})
				`uvm_fatal(this.get_name(), "cannot randomize row_cfg!")
			
			sfc_cfg = SurfaceCfg::type_id::create();
			if(!sfc_cfg.randomize() with{
				len_foreach_sfc == cfg.sfc_data_n_foreach_fmrow[i];
			})
				`uvm_fatal(this.get_name(), "cannot randomize sfc_cfg!")
			
			row.set_configuration(row_cfg);
			
			for(int unsigned j = 0;j < row_cfg.sfc_n;j++)
			begin
				FmapSfc sfc;
				
				sfc = FmapSfc::type_id::create();
				sfc.set_configuration(sfc_cfg);
				
				for(int unsigned k = 0;k < sfc_cfg.len_foreach_sfc;k++)
					// void'(sfc.set_pt(k, (i << 8) | ((j + k) % 256)));
					void'(sfc.set_pt(k, $random()));
				
				void'(row.set_sfc(j, sfc));
			end
			
			void'(row.finish_adding_sfc());
			row.set_baseaddr(cfg.abs_baseaddr_foreach_fmrow[i] - cfg.fmap_mem_baseaddr);
			
			this.feature_map.put_fmap_row(cfg.actual_sfc_rid_foreach_fmrow[i], row);
		end
		
		this.feature_map.finish_adding_fmap_row();
		this.feature_map.set_baseaddr(cfg.fmap_mem_baseaddr);
	endfunction
	
	function Fmap get_feature_map();
		return this.feature_map;
	endfunction
	
	`uvm_object_utils(FmapBuilder)
	
endclass

class KernalSetBuilder extends uvm_object;
	
	local KernalSet kernal_set;
	
	function new(string name = "KernalSetBuilder");
		super.new(name);
		
		this.kernal_set = KernalSet::type_id::create();
	endfunction
	
	function void build_default_kernal_set(const ref ConvDataHubCfg cfg);
		int unsigned now_cgrpid;
		
		now_cgrpid = 0;
		
		for(int unsigned k = 0;k < cfg.total_kernal_set_n;k++)
		begin
			int unsigned now_cgrp_n;
			int unsigned now_wgtblk_w;
			
			now_cgrp_n = cfg.cgrpn_foreach_kernal_set[k];
			now_wgtblk_w = cfg.wgtblk_w_foreach_kernal_set[k];
			
			for(int unsigned c = 0;c < now_cgrp_n;c++)
			begin
				int unsigned now_sfc_depth;
				KernalCGrp kernal_cgrp;
				KernalCGrpCfg kernal_cgrp_cfg;
				KernalWgtBlkCfg kernal_wgtblk_cfg;
				
				now_sfc_depth = cfg.depth_foreach_kernal_cgrp[now_cgrpid];
				kernal_cgrp = KernalCGrp::type_id::create();
				kernal_cgrp_cfg = KernalCGrpCfg::type_id::create();
				if(!kernal_cgrp_cfg.randomize() with{
					len_foreach_sfc == now_sfc_depth;
					sfc_n_foreach_wgt_blk == now_wgtblk_w;
					kernal_shape == cfg.kernal_shape;
				})
				begin
					`uvm_fatal(this.get_name(), "cannot randomize kernal_cgrp_cfg!")
				end
				kernal_wgtblk_cfg = KernalWgtBlkCfg::type_id::create();
				if(!kernal_wgtblk_cfg.randomize() with{
					len_foreach_sfc == now_sfc_depth;
					sfc_n == now_wgtblk_w;
				})
				begin
					`uvm_fatal(this.get_name(), "cannot randomize kernal_wgtblk_cfg!")
				end
				
				kernal_cgrp.set_configuration(kernal_cgrp_cfg);
				
				for(int unsigned w = 0;w < kernal_cgrp.get_size();w++)
				begin
					KernalWgtBlk kernal_wgt_blk;
					
					kernal_wgt_blk = KernalWgtBlk::type_id::create();
					
					kernal_wgt_blk.set_configuration(kernal_wgtblk_cfg);
					
					for(int unsigned s = 0;s < now_wgtblk_w;s++)
					begin
						KernalSfc kernal_sfc;
						
						kernal_sfc = KernalSfc::type_id::create();
						
						kernal_sfc.set_configuration(kernal_wgtblk_cfg);
						
						for(int unsigned i = 0;i < now_sfc_depth;i++)
							kernal_sfc.set_pt(i, $random());
						
						kernal_wgt_blk.set_sfc(s, kernal_sfc);
					end
					
					kernal_wgt_blk.finish_adding_sfc();
					
					kernal_cgrp.set_wgt_blk(w, kernal_wgt_blk);
				end
				
				kernal_cgrp.finish_adding_wgt_blk();
				kernal_cgrp.set_baseaddr(cfg.abs_baseaddr_foreach_cgrp[now_cgrpid] - cfg.kernal_mem_baseaddr);
				
				this.kernal_set.put_kernal_cgrp(now_cgrpid, kernal_cgrp);
				
				now_cgrpid++;
			end
		end
		
		this.kernal_set.finish_adding_kernal_cgrp();
		this.kernal_set.set_baseaddr(cfg.kernal_mem_baseaddr);
	endfunction
	
	function KernalSet get_kernal_set();
		return this.kernal_set;
	endfunction
	
	`uvm_object_utils(KernalSetBuilder)
	
endclass

class PandaMemoryAdapter extends panda_memory #(
	.ADDR_WIDTH(32),
	.DATA_WIDTH(256)
);
	
	DataBlk data_blk;
	
	function new(DataBlk data_blk = null, string name = "PandaMemoryAdapter", int data_width = DATA_WIDTH);
		super.new(name, data_width);
		
		this.data_blk = data_blk;
		
		if(data_blk != null)
		begin
			for(int unsigned i = 0;i < data_blk.get_len_in_byte();i++)
			begin
				logic[7:0] now_byte;
				
				now_byte = data_blk.get_byte_by_addr(i);
				
				if(!$isunknown(now_byte))
					this.memory[data_blk.get_baseaddr() + i] = now_byte;
			end
		end
	endfunction
	
	`uvm_object_utils_begin(PandaMemoryAdapter)
		`uvm_field_int(default_data, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(byte_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_aa_int_int(memory, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	
endclass

`endif
