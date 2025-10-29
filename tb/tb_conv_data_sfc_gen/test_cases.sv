`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class FmapKwgtStrmMAxisSqc #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer EXTRA_DATA_WIDTH = 4 // 随路传输附加数据的位宽(必须>=1)
)extends uvm_sequence;
	
	local AXISTrans #(.data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)) axis_trans;
	
	rand int unsigned sfc_n; // 表面总数
	rand bit[4:0] vld_data_n_of_each_sfc; // 每个表面的有效数据个数 - 1
	rand bit[EXTRA_DATA_WIDTH-1:0] extra_data; // 随路传输附加数据
	
	local int unsigned pkt_len; // 数据包长度
	local bit[STREAM_DATA_WIDTH/8-1:0] last_trans_keep; // 最后1次传输的keep信号
	
	// 注册object
	`uvm_object_param_utils(FmapKwgtStrmMAxisSqc #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)))
	
	virtual task body();
		automatic int unsigned total_hw_n = this.sfc_n * ({1'b0, this.vld_data_n_of_each_sfc} + 1); // 数据包总半字数
		
		this.pkt_len = 
			total_hw_n / (STREAM_DATA_WIDTH / 16) + 
			((total_hw_n % (STREAM_DATA_WIDTH / 16)) ? 1:0);
		
		if((total_hw_n % (STREAM_DATA_WIDTH / 16)) == 0)
		begin
			this.last_trans_keep = {(STREAM_DATA_WIDTH/8){1'b1}};
		end
		else
		begin
			this.last_trans_keep = 0;
			
			repeat(total_hw_n % (STREAM_DATA_WIDTH / 16))
			begin
				this.last_trans_keep <<= 2;
				this.last_trans_keep[1:0] = 2'b11;
			end
		end
		
		`uvm_do_with(this.axis_trans, {
			data_n == pkt_len;
			
			data.size() == data_n;
			keep.size() == data_n;
			strb.size() == data_n;
			user.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i] == (i+1);
			}
			
			foreach(keep[i]){
				if(i == (data_n-1))
					keep[i] == last_trans_keep;
				else
					keep[i] == {(STREAM_DATA_WIDTH/8){1'b1}};
			}
			
			foreach(user[i]){
				user[i][4:0] == vld_data_n_of_each_sfc;
				user[i][5+EXTRA_DATA_WIDTH-1:5] == extra_data;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 2;
			}
		})
	endtask
	
endclass

class ConvDataSfcGenCase0Sqc #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	integer EXTRA_DATA_WIDTH = 4 // 随路传输附加数据的位宽(必须>=1)
)extends uvm_sequence;
	
	local FmapKwgtStrmMAxisSqc #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)) strm_m_axis_sqc;
	
	// 注册object
	`uvm_object_param_utils(ConvDataSfcGenCase0Sqc #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_do_with(this.strm_m_axis_sqc, {
			strm_m_axis_sqc.sfc_n == 9;
			strm_m_axis_sqc.vld_data_n_of_each_sfc == 0;
			strm_m_axis_sqc.extra_data == 13;
		})
		
		for(int i = 0;i < 500;i++)
		begin
			`uvm_do_with(this.strm_m_axis_sqc, {
				strm_m_axis_sqc.sfc_n inside {[20:28]};
				strm_m_axis_sqc.vld_data_n_of_each_sfc <= (ATOMIC_C-1);
				strm_m_axis_sqc.extra_data == ((i+1)%(1<<EXTRA_DATA_WIDTH));
			})
		end
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ConvDataSfcGenBaseTest #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	integer EXTRA_DATA_WIDTH = 4, // 随路传输附加数据的位宽(必须>=1)
	real SIM_DELAY = 1 // 仿真延时
)extends uvm_test;
	
	// 特征图/卷积核表面生成单元测试环境
	local ConvDataSfcGenEnv #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH), .SIM_DELAY(SIM_DELAY)) env;
	
	// 注册component
	`uvm_component_param_utils(ConvDataSfcGenBaseTest #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "ConvDataSfcGenBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = ConvDataSfcGenEnv #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH), .SIM_DELAY(SIM_DELAY))::type_id::create("env", this); // 创建env
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		phase.phase_done.set_drain_time(this, 10 * (10 ** 6));
	endtask
	
endclass

class ConvDataSfcGenCase0Test extends ConvDataSfcGenBaseTest #(.STREAM_DATA_WIDTH(32), .ATOMIC_C(4), .EXTRA_DATA_WIDTH(4), .SIM_DELAY(1));
	
	// 注册component
	`uvm_component_utils(ConvDataSfcGenCase0Test)
	
	function new(string name = "ConvDataSfcGenCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			ConvDataSfcGenCase0Sqc #(.STREAM_DATA_WIDTH(32), .ATOMIC_C(4), .EXTRA_DATA_WIDTH(4))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("ConvDataSfcGenCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
