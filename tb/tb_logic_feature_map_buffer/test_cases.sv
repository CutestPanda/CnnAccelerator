`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

class LogicFmapBufferFinMAxisSqc #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	local AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(22)) trans; // 特征图表面行数据输入AXIS主机事务
	
	rand int unsigned trans_data_n; // 写表面个数
	rand bit[9:0] row_id; // 待写表面行编号
	rand bit[11:0] actual_rid; // 实际表面行号
	
	// 注册object
	`uvm_object_param_utils(LogicFmapBufferFinMAxisSqc #(.ATOMIC_C(ATOMIC_C)))
	
	virtual task body();
		`uvm_do_with(this.trans, {
			trans.data_n == trans_data_n;
			
			trans.data.size() == trans.data_n;
			trans.keep.size() == trans.data_n;
			trans.strb.size() == trans.data_n;
			trans.user.size() == trans.data_n;
			trans.last.size() == trans.data_n;
			
			trans.wait_period_n.size() == trans.data_n;
			
			foreach(trans.data[i]){
				trans.data[i] == {(ATOMIC_C*2){i[7:0]}};
			}
			
			foreach(trans.keep[i]){
				trans.keep[i] == {(ATOMIC_C*2){1'b1}};
			}
			
			foreach(trans.user[i]){
				trans.user[i] == {actual_rid, row_id};
			}
			
			foreach(trans.last[i]){
				trans.last[i] == (i == (trans.data_n - 1));
			}
			
			foreach(trans.wait_period_n[i]){
				trans.wait_period_n[i] <= 2;
			}
		})
	endtask
	
endclass

class LogicFmapBufferRdReqMAxisSqc #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	local AXISTrans #(.data_width(40), .user_width(0)) trans; // 特征图表面行读请求AXIS主机事务
	
	rand bit auto_rplc; // 是否需要自动置换表面行
	rand bit[9:0] rid; // 表面行的缓存编号
	rand bit[11:0] start_sfc_id; // 起始表面编号
	rand bit[11:0] sfc_n; // 待读取的表面个数 - 1
	
	// 注册object
	`uvm_object_param_utils(LogicFmapBufferRdReqMAxisSqc #(.ATOMIC_C(ATOMIC_C)))
	
	virtual task body();
		`uvm_do_with(this.trans, {
			trans.data_n == 1;
			
			trans.data.size() == 1;
			trans.keep.size() == 1;
			trans.strb.size() == 1;
			trans.user.size() == 1;
			trans.last.size() == 1;
			trans.wait_period_n.size() == 1;
			
			trans.data[0] == {5'd0, auto_rplc, rid, start_sfc_id, sfc_n};
			trans.last[0] == 1'b1;
			trans.wait_period_n[0] <= 6;
		})
	endtask
	
endclass

class LogicFmapBufferCase0VSqc #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	local ReqAckTrans #(.req_payload_width(0), .resp_payload_width(0)) rst_buf_trans; // 重置缓存REQ-ACK主机事务
	local ReqAckTrans #(.req_payload_width(10), .resp_payload_width(0)) sfc_row_rplc_trans; // 表面行置换REQ-ACK主机事务
	local ReqAckTrans #(.req_payload_width(12), .resp_payload_width(0)) sfc_row_search_trans; // 表面行检索REQ-ACK主机事务
	
	local LogicFmapBufferFinMAxisSqc #(.ATOMIC_C(ATOMIC_C)) m_fin_axis_sqc;
	local LogicFmapBufferRdReqMAxisSqc #(.ATOMIC_C(ATOMIC_C)) m_rd_req_axis_sqc;
	
	// 注册object
	`uvm_object_param_utils(LogicFmapBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C)))
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(LogicFmapBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_do_on_with(this.rst_buf_trans, p_sequencer.rst_buf_sqr, {
			rst_buf_trans.req_wait_period_n == 10;
		})
		
		# (10 * 600);
		
		`uvm_do_on_with(this.m_fin_axis_sqc, p_sequencer.m_fin_axis_sqr, {
			m_fin_axis_sqc.trans_data_n inside {[5:20]};
			m_fin_axis_sqc.row_id == 1;
			m_fin_axis_sqc.actual_rid == 18;
		})
		
		# (10 * 10);
		
		`uvm_do_on_with(this.m_rd_req_axis_sqc, p_sequencer.m_rd_req_axis_sqr, {
			m_rd_req_axis_sqc.auto_rplc == 1'b0;
			m_rd_req_axis_sqc.rid == 1;
			m_rd_req_axis_sqc.start_sfc_id <= 8;
			m_rd_req_axis_sqc.sfc_n == (20 - 1);
		})
		
		# (10 * 40);
		
		fork
			`uvm_do_on_with(this.sfc_row_search_trans, p_sequencer.sfc_row_search_sqr, {
				sfc_row_search_trans.req_wait_period_n == 1;
				sfc_row_search_trans.req_payload[11:0] == 18;
			})
			
			`uvm_do_on_with(this.m_fin_axis_sqc, p_sequencer.m_fin_axis_sqr, {
				m_fin_axis_sqc.trans_data_n inside {[5:20]};
				m_fin_axis_sqc.row_id == 1;
				m_fin_axis_sqc.actual_rid == 25;
			})
			
			`uvm_do_on_with(this.sfc_row_rplc_trans, p_sequencer.sfc_row_rplc_sqr, {
				sfc_row_rplc_trans.req_wait_period_n == 8;
				sfc_row_rplc_trans.req_payload[9:0] == 1;
			})
		join
		
		`uvm_do_on_with(this.sfc_row_search_trans, p_sequencer.sfc_row_search_sqr, {
			sfc_row_search_trans.req_wait_period_n == 1;
			sfc_row_search_trans.req_payload[11:0] == 18;
		})
		
		`uvm_do_on_with(this.sfc_row_search_trans, p_sequencer.sfc_row_search_sqr, {
			sfc_row_search_trans.req_wait_period_n == 1;
			sfc_row_search_trans.req_payload[11:0] == 25;
		})
		
		fork
			`uvm_do_on_with(this.sfc_row_search_trans, p_sequencer.sfc_row_search_sqr, {
				sfc_row_search_trans.req_wait_period_n == 2;
				sfc_row_search_trans.req_payload[11:0] == 20;
			})
			
			`uvm_do_on_with(this.m_rd_req_axis_sqc, p_sequencer.m_rd_req_axis_sqr, {
				m_rd_req_axis_sqc.auto_rplc == 1'b0;
				m_rd_req_axis_sqc.rid == 2;
				m_rd_req_axis_sqc.start_sfc_id <= 8;
				m_rd_req_axis_sqc.sfc_n == (20 - 1);
			})
		join
		
		fork
			`uvm_do_on_with(this.m_fin_axis_sqc, p_sequencer.m_fin_axis_sqr, {
				m_fin_axis_sqc.trans_data_n inside {[5:20]};
				m_fin_axis_sqc.row_id == 5;
				m_fin_axis_sqc.actual_rid == 6;
			})
			
			`uvm_do_on_with(this.m_rd_req_axis_sqc, p_sequencer.m_rd_req_axis_sqr, {
				m_rd_req_axis_sqc.auto_rplc == 1'b1;
				m_rd_req_axis_sqc.rid == 3;
				m_rd_req_axis_sqc.start_sfc_id <= 8;
				m_rd_req_axis_sqc.sfc_n == (20 - 1);
			})
		join
		
		fork
			begin
				`uvm_do_on_with(this.m_fin_axis_sqc, p_sequencer.m_fin_axis_sqr, {
					m_fin_axis_sqc.trans_data_n inside {[5:20]};
					m_fin_axis_sqc.row_id == 6;
					m_fin_axis_sqc.actual_rid == 1;
				})
				
				`uvm_do_on_with(this.m_fin_axis_sqc, p_sequencer.m_fin_axis_sqr, {
					m_fin_axis_sqc.trans_data_n inside {[5:20]};
					m_fin_axis_sqc.row_id == 5;
					m_fin_axis_sqc.actual_rid == 97;
				})
			end
			
			begin
				# (10 * 50);
				
				`uvm_do_on_with(this.m_rd_req_axis_sqc, p_sequencer.m_rd_req_axis_sqr, {
					m_rd_req_axis_sqc.auto_rplc == 1'b1;
					m_rd_req_axis_sqc.rid == 5;
					m_rd_req_axis_sqc.start_sfc_id <= 8;
					m_rd_req_axis_sqc.sfc_n == (32 - 1);
				})
			end
		join
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class LogicFmapBufferBaseTest #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real SIM_DELAY = 1 // 仿真延时
)extends uvm_test;
	
	// (逻辑)特征图缓存测试环境
	local LogicFmapBufferEnv #(.ATOMIC_C(ATOMIC_C), .SIM_DELAY(SIM_DELAY)) env;
	
	// 注册component
	`uvm_component_param_utils(LogicFmapBufferBaseTest #(.ATOMIC_C(ATOMIC_C), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "LogicFmapBufferBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = LogicFmapBufferEnv #(.ATOMIC_C(ATOMIC_C), .SIM_DELAY(SIM_DELAY))::type_id::create("env", this); // 创建env
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		phase.phase_done.set_drain_time(this, 10 * (10 ** 6));
	endtask
	
endclass

class LogicFmapBufferCase0Test extends LogicFmapBufferBaseTest #(.ATOMIC_C(2), .SIM_DELAY(1));
	
	localparam integer ATOMIC_C = 2; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	// 注册component
	`uvm_component_utils(LogicFmapBufferCase0Test)
	
	function new(string name = "LogicFmapBufferCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.v_sqr.main_phase", 
			"default_sequence", 
			LogicFmapBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("LogicFmapBufferCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
