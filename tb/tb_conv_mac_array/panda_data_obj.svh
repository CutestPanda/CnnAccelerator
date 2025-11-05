`ifndef __PANDA_DATA_OBJ_H
`define __PANDA_DATA_OBJ_H

`define OP_TYPE_ADD 1
`define OP_TYPE_SUB 2
`define OP_TYPE_MUL 3
`define OP_TYPE_DIV 4

`define panda_declare_abstract_data_op_func(FUN_NAME, THIS_TYPE, OP_TYPE) \
virtual function AbstractData ``FUN_NAME``(AbstractData op); \
	``THIS_TYPE`` packed_data; \
	``THIS_TYPE`` res; \
	if($cast(packed_data, op)) \
	begin \
		res = ``THIS_TYPE``::type_id::create(); \
		if(``OP_TYPE`` == `OP_TYPE_ADD) \
			res.data = this.data + packed_data.data; \
		else if(``OP_TYPE`` == `OP_TYPE_SUB) \
			res.data = this.data - packed_data.data; \
		else if(``OP_TYPE`` == `OP_TYPE_MUL) \
			res.data = this.data * packed_data.data; \
		else \
			res.data = this.data / packed_data.data; \
		return res; \
	end \
	else \
	begin \
		`uvm_error(this.get_name(), "cannot convert op!") \
		return null; \
	end \
endfunction

class IntErrorValue extends uvm_object;
	
	longint max_err;
	longint avg_err;
	real max_err_rate;
	
	`tue_object_default_constructor(IntErrorValue)
	
	`uvm_object_utils_begin(IntErrorValue)
		`uvm_field_int(max_err, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(avg_err, UVM_DEFAULT | UVM_DEC)
		`uvm_field_real(max_err_rate, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class RealErrorValue extends uvm_object;
	
	real max_err;
	real avg_err;
	real max_err_rate;
	
	`tue_object_default_constructor(RealErrorValue)
	
	`uvm_object_utils_begin(RealErrorValue)
		`uvm_field_real(max_err, UVM_DEFAULT)
		`uvm_field_real(avg_err, UVM_DEFAULT)
		`uvm_field_real(max_err_rate, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

virtual class AbstractData extends uvm_object;
	
	pure virtual function AbstractData add(AbstractData op);
	pure virtual function AbstractData sum(AbstractData op);
	pure virtual function AbstractData mul(AbstractData op);
	pure virtual function AbstractData div(AbstractData op);
	pure virtual function void mul_add_accum(AbstractData op1, AbstractData op2);
	
	pure virtual function bit[15:0] encode_to_int16();
	pure virtual function void set_by_int16(bit[15:0] int16);
	pure virtual function void set_to_zero();
	
	pure virtual function void upd_err(uvm_object err_v, AbstractData op);
	
	pure virtual function void print_data(uvm_printer printer, string field_name = "");
	
	`tue_object_default_constructor(AbstractData)
	
endclass

class PackedReal extends AbstractData;
	
	rand real data;
	
	`panda_declare_abstract_data_op_func(add, PackedReal, `OP_TYPE_ADD)
	`panda_declare_abstract_data_op_func(sum, PackedReal, `OP_TYPE_SUB)
	`panda_declare_abstract_data_op_func(mul, PackedReal, `OP_TYPE_MUL)
	`panda_declare_abstract_data_op_func(div, PackedReal, `OP_TYPE_DIV)
	
	virtual function void mul_add_accum(AbstractData op1, AbstractData op2);
		PackedReal op1_cvt;
		PackedReal op2_cvt;
		
		if(!$cast(op1_cvt, op1))
		begin
			`uvm_error(this.get_name(), "cannot cast op1!")
			
			return;
		end
		
		if(!$cast(op2_cvt, op2))
		begin
			`uvm_error(this.get_name(), "cannot cast op2!")
			
			return;
		end
		
		this.data += (op1_cvt.data * op2_cvt.data);
	endfunction
	
	virtual function bit[15:0] encode_to_int16();
		int unsigned cvt_res;
		
		cvt_res = encode_fp16(this.data);
		
		return cvt_res[15:0];
	endfunction
	
	virtual function void set_by_int16(bit[15:0] int16);
		this.data = decode_fp16(int16);
	endfunction
	
	virtual function void set_to_zero();
		this.data = 0.0;
	endfunction
	
	virtual function void print_data(uvm_printer printer, string field_name = "");
		printer.print_real(field_name, this.data);
	endfunction
	
	virtual function void upd_err(uvm_object err_v, AbstractData op);
		RealErrorValue err_v_cvt;
		PackedReal op_cvt;
		
		real now_err;
		real now_err_rate;
		
		if(!$cast(err_v_cvt, err_v))
		begin
			`uvm_error(this.get_name(), "cannot cast err_v!")
			
			return;
		end
		
		if(!$cast(op_cvt, op))
		begin
			`uvm_error(this.get_name(), "cannot cast op!")
			
			return;
		end
		
		now_err = op_cvt.data - this.data;
		
		if((this.data != 0.0) && (op_cvt.data != 0.0))
			now_err_rate = now_err / this.data;
		else
			now_err_rate = 0.0;
		
		if(now_err < 0.0)
			now_err = -now_err;
		
		if(now_err_rate < 0.0)
			now_err_rate = -now_err_rate;
		
		if(now_err > err_v_cvt.max_err)
			err_v_cvt.max_err = now_err;
		
		if(now_err_rate > err_v_cvt.max_err_rate)
			err_v_cvt.max_err_rate = now_err_rate;
		
		err_v_cvt.avg_err += now_err;
	endfunction
	
	`tue_object_default_constructor(PackedReal)
	
	`uvm_object_utils_begin(PackedReal)
		`uvm_field_real(data, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class PackedShortInt extends AbstractData;
	
	rand shortint data;
	
	`panda_declare_abstract_data_op_func(add, PackedShortInt, `OP_TYPE_ADD)
	`panda_declare_abstract_data_op_func(sum, PackedShortInt, `OP_TYPE_SUB)
	`panda_declare_abstract_data_op_func(mul, PackedShortInt, `OP_TYPE_MUL)
	`panda_declare_abstract_data_op_func(div, PackedShortInt, `OP_TYPE_DIV)
	
	virtual function void mul_add_accum(AbstractData op1, AbstractData op2);
		PackedShortInt op1_cvt;
		PackedShortInt op2_cvt;
		
		if(!$cast(op1_cvt, op1))
		begin
			`uvm_error(this.get_name(), "cannot cast op1!")
			
			return;
		end
		
		if(!$cast(op2_cvt, op2))
		begin
			`uvm_error(this.get_name(), "cannot cast op2!")
			
			return;
		end
		
		this.data += (op1_cvt.data * op2_cvt.data);
	endfunction
	
	virtual function bit[15:0] encode_to_int16();
		return this.data[15:0];
	endfunction
	
	virtual function void set_by_int16(bit[15:0] int16);
		this.data[15:0] = int16;
	endfunction
	
	virtual function void set_to_zero();
		this.data = 0;
	endfunction
	
	virtual function void print_data(uvm_printer printer, string field_name = "");
		printer.print_int(field_name, this.data, 16, UVM_DEC);
	endfunction
	
	virtual function void upd_err(uvm_object err_v, AbstractData op);
		`uvm_fatal(this.get_name(), "not implement!")
	endfunction
	
	`tue_object_default_constructor(PackedShortInt)
	
	`uvm_object_utils_begin(PackedShortInt)
		`uvm_field_int(data, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

virtual class AbstractSurface extends uvm_object;
	
	rand int len;
	
	AbstractData org_data[];
	bit[15:0] fmt_data[];
	
	constraint c_valid_len{
		len >= 1;
	}
	
	virtual function void format_data_array();
		this.fmt_data = new[this.len];
		
		for(int i = 0;i < this.len;i++)
			this.fmt_data[i] = this.org_data[i].encode_to_int16();
	endfunction
	
	pure virtual function void restore_data_array();
	
	virtual function void print_fmt_data_element(uvm_printer printer, int index, string suffix = "");
		this.org_data[index].print_data(printer, $sformatf("org_data%0s", suffix));
	endfunction
	
	pure virtual function uvm_object cmp_err(AbstractSurface sfc, output bit err_flag);
	pure virtual function AbstractData mul_add(AbstractSurface op);
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		printer.print_int("len", this.len, 32, UVM_DEC);
		
		for(int i = 0;i < this.len;i++)
			this.print_fmt_data_element(printer, i, $sformatf("[%0d]", i));
	endfunction
	
	`tue_object_default_constructor(AbstractSurface)
	
endclass

class Fp16Surface extends AbstractSurface;
	
	virtual function void restore_data_array();
		this.org_data = new[this.len];
		
		for(int i = 0;i < this.len;i++)
		begin
			this.org_data[i] = PackedReal::type_id::create();
			
			this.org_data[i].set_by_int16(this.fmt_data[i]);
		end
	endfunction
	
	virtual function uvm_object cmp_err(AbstractSurface sfc, output bit err_flag);
		RealErrorValue err_v;
		
		if(this.org_data.size() != sfc.org_data.size())
		begin
			err_flag = 1'b1;
			
			return null;
		end
		
		err_v = RealErrorValue::type_id::create("real_err");
		
		err_v.max_err = 0.0;
		err_v.avg_err = 0.0;
		err_v.max_err_rate = 0.0;
		
		for(int i = 0;i < this.org_data.size();i++)
			this.org_data[i].upd_err(err_v, sfc.org_data[i]);
		
		err_v.avg_err /= this.org_data.size();
		
		if(err_v.max_err_rate >= 0.5)
			err_flag = 1'b1;
		else
			err_flag = 1'b0;
		
		return err_v;
	endfunction
	
	virtual function AbstractData mul_add(AbstractSurface op);
		AbstractData res;
		
		res = PackedReal::type_id::create();
		
		res.set_to_zero();
		
		if(this.org_data.size() != op.org_data.size())
			return null;
		
		for(int i = 0;i < this.org_data.size();i++)
			res.mul_add_accum(this.org_data[i], op.org_data[i]);
		
		return res;
	endfunction
	
	`tue_object_default_constructor(Fp16Surface)
	`uvm_object_utils(Fp16Surface)
	
endclass

class Int16Surface extends AbstractSurface;
	
	virtual function void restore_data_array();
		this.org_data = new[this.len];
		
		for(int i = 0;i < this.len;i++)
		begin
			this.org_data[i] = PackedShortInt::type_id::create();
			this.org_data[i].set_by_int16(this.fmt_data[i]);
		end
	endfunction
	
	virtual function uvm_object cmp_err(AbstractSurface sfc, output bit err_flag);
		`uvm_fatal(this.get_name(), "not implement!")
		
		return null;
	endfunction
	
	virtual function AbstractData mul_add(AbstractSurface op);
		`uvm_fatal(this.get_name(), "not implement!")
		
		return null;
	endfunction
	
	`tue_object_default_constructor(Int16Surface)
	`uvm_object_utils(Int16Surface)
	
endclass

`undef OP_TYPE_ADD
`undef OP_TYPE_SUB
`undef OP_TYPE_MUL
`undef OP_TYPE_DIV
`undef panda_declare_abstract_data_op_func

`endif
