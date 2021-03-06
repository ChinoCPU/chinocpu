`include "defines.v"

module ex(

	input wire						rst,
	
	//从ID阶段传来的消息
	input wire[`AluOpBus]         	aluop_i,
	input wire[`AluSelBus]        	alusel_i,
	input wire[`RegBus]           	reg1_i,
	input wire[`RegBus]           	reg2_i,
	input wire[`RegAddrBus]       	wd_i,
	input wire                    	wreg_i,
	input wire[`RegBus]				offset_i,

	//输出到MEM阶段的信息
	output reg[`RegAddrBus]       	wd_o,
	output reg                    	wreg_o,
	output reg[`RegBus]				wdata_o,

	output reg[`RegBus]				hi_o,
	output reg[`RegBus]				lo_o,
	output reg						we_o,
	output reg[`RegBus]				flags,

	//送到CTRL模块的信息
	output reg 						stallreq,

	//串行除法计算
	input wire[`DoubleRegBus]		result_i,
	input wire 						ready_i,

	//延迟槽指令
	input wire 						ex_is_in_delayslot,

	output reg 						signed_div_o,
	output reg						div_start_o,
	output reg 						div_annul_i,
	output reg[`RegBus]				div_op1,
	output reg[`RegBus]				div_op2,
	output reg[`RegBus]				ex_addr,
	output reg[`AluOpBus]			ex_aluop,
	output reg[`RegBus]				ex_reg2,

	input wire[`RegBus]				cp0_reg_data_i,
	output reg[`RegAddrBus]			cp0_reg_raddr_o,

	input wire[`RegAddrBus]			mem_cp0_reg_waddr,
	input wire[`RegBus]				mem_cp0_reg_data,
	input wire						mem_cp0_reg_we,

	input wire[`RegAddrBus]			wb_cp0_reg_waddr,
	input wire[`RegBus]				wb_cp0_reg_data,
	input wire						wb_cp0_reg_we,

	output reg						cp0_reg_we_o,
	output reg[`RegAddrBus]			cp0_reg_waddr_o,
	output reg[`RegBus]				cp0_reg_data_o,
	input wire[`InstBus]			inst_i,

	input wire[`RegBus]  			excepttype_i,
	input wire[`RegBus]				current_inst_address_i,

	output wire[`RegBus]			excepttype_o,
	output wire						is_in_delayslot_o,
	output wire[`RegBus]			current_inst_address_o
);

	reg[`RegBus] 			logicout;
	reg[`RegBus] 			shiftout;
	reg[`RegBus] 			movout;
	reg[`DoubleRegBus]		mulout;	//保存乘法的运算结果
	wire[`AriRegBus]		reg2_i_mux;
	wire[`AriRegBus]		result_arithmetic;
	wire[`RegBus]			mul_reg2_mux;
	wire[`RegBus]			mul_reg1_mux;
	wire[`DoubleRegBus]		mulres_temp;
	reg 					div_stallreq;	//除法运算导致流水线暂停
	reg[`AriRegBus]			temp_addr;
	reg  					trapassert;
	
	assign excepttype_o = {excepttype_i[31:12],1'b0,trapassert,excepttype_i[9:8],8'h00};
	assign is_in_delayslot_o = ex_is_in_delayslot;
	assign current_inst_address_o = current_inst_address_i;

	//trap指令
	always @(*) begin
		if (rst == `RstEnable) begin
			trapassert <= `TrapAssert;
		end else begin
			if (aluop_i == `EXE_TRAP_OP)
				trapassert <= `TrapAssert;
			else
				trapassert <= `TrapNotAssert;
		end
	end
	//减法运算则计算补码
	assign reg2_i_mux = (aluop_i == `EXE_SUB_OP) ? (~{1'b0,reg2_i}) + 1:{1'b0,reg2_i};
	assign result_arithmetic = {1'b0,reg1_i} + reg2_i_mux;
	// 指令地址的计算
	always @ (*) begin
		if(rst == `RstEnable) begin
			temp_addr <= 33'h0;
		end else begin
			temp_addr <= reg1_i + offset_i;
			if (temp_addr[32:32] == 1'b1)	// 地址溢出则回滚地址
				temp_addr <= temp_addr - 32'hffffffff;
			ex_addr <= temp_addr[31:0];
			ex_reg2 <= reg2_i;
			ex_aluop <= aluop_i;
		end
	end

	always @ (*) begin
		if(rst == `RstEnable) begin
			logicout <= `ZeroWord;
		end else begin
			case (aluop_i)
				`EXE_OR_OP:logicout <= reg1_i | reg2_i;
				`EXE_AND_OP:logicout <= reg1_i & reg2_i;
				`EXE_XOR_OP:logicout <= reg1_i ^ reg2_i;
				`EXE_NOT_OP:logicout <= ~reg1_i;
				default:logicout <= `ZeroWord;
			endcase
		end    //if
	end      //always

	always @(*) begin
		if (rst == `RstEnable) begin
			shiftout <= `ZeroWord;
		end else begin
			case (aluop_i)
				`EXE_SHL_OP:shiftout <= reg1_i << reg2_i[4:0];
				`EXE_SHR_OP:shiftout <= reg1_i >> reg2_i[4:0];
				//算术右移
				`EXE_SAR_OP:begin
					shiftout <= ({32{reg1_i[31]}} << (6'd32-{1'b0, reg2_i[4:0]})) 
								| reg1_i >> reg2_i[4:0];
				end
				default:shiftout <= `ZeroWord;
			endcase
		end
	end
	//assign cp0_reg_raddr_o = inst_i[51:47];
	always @(*) begin
		if (rst == `RstEnable)
			movout <= `ZeroWord;
		else begin
			case(aluop_i)
				`EXE_MOV_OP:movout <= reg1_i;
				`EXE_MOVZ_OP:movout <= reg2_i;
				`EXE_MOVN_OP:movout <= reg2_i;
				`EXE_MFC_OP: begin
					cp0_reg_raddr_o <= inst_i[51:47];
					movout <= cp0_reg_data_i;
					//解决数据相关
					if (mem_cp0_reg_we == `WriteEnable && mem_cp0_reg_waddr == inst_i[51:47])
						movout <= mem_cp0_reg_data;
					else if (wb_cp0_reg_we == `WriteEnable && wb_cp0_reg_waddr == inst_i[51:47])
						movout <= wb_cp0_reg_data;
				end
				default:begin
				end
			endcase
		end
	end

	always @(*) begin
		if (rst == `RstEnable)
			flags <= `ZeroWord;
		else
			if (aluop_i == `EXE_SUB_OP || aluop_i == `EXE_ADD_OP) begin
				flags[0] <= ((!reg2_i_mux[31] && !reg1_i[31]) && result_arithmetic[31])
							|| ((reg2_i_mux[31] && reg1_i[31]) && !result_arithmetic[31]);	//溢出标志位
				flags[1] <= result_arithmetic[32];//无符号整数进位标志位
			end else
				flags <= flags;
	end

	assign mul_reg1_mux = ((aluop_i == `EXE_MULT_OP) && reg1_i[31]) ? (~reg1_i) + 1:reg1_i;
	assign mul_reg2_mux = ((aluop_i == `EXE_MULT_OP) && reg2_i[31]) ? (~reg2_i) + 1:reg2_i;

	assign mulres_temp = mul_reg1_mux * mul_reg2_mux;

	always @(*) begin
		if (rst == `RstEnable)
			mulout <= `ZeroDoubleWord;
		else if (aluop_i == `EXE_MULT_OP) begin
			if (reg1_i[31] ^ reg2_i[31]) begin
				//正数 * 负数，对结果取补码
				mulout <= ~mulres_temp + 1;
			end else begin
				mulout <= mulres_temp;
			end
		end else begin
			mulout <= mulres_temp;
		end
	end

	//串行除法运算
	always @(*) begin
		if (rst == `RstEnable) begin
			div_stallreq <= `NoStop;
			div_op1 <= `ZeroWord;
			div_op2 <= `ZeroWord;
			div_start_o <= `DivStop;
			signed_div_o <= `DivStop;
		end else begin
			div_stallreq <= `NoStop;
			div_op1 <= `ZeroWord;
			div_op2 <= `ZeroWord;
			div_start_o <= `DivStop;
			signed_div_o <= `DivStop;
			case(aluop_i)
				`EXE_DIV_OP:begin
					if (ready_i == `DivResNotReady) begin
						div_op1 <= reg1_i;
						div_op2 <= reg2_i;
						div_start_o <= `DivStart;
						div_annul_i <= 1'b0;
						signed_div_o <= 1'b1;
						div_stallreq <= `Stop;		//暂停流水线
					end else if (ready_i == `DivResReady) begin
						div_op1 <= reg1_i;
						div_op2 <= reg2_i;
						div_start_o <= `DivStop;
						signed_div_o <= 1'b1;
						div_annul_i <= 1'b1;
						div_stallreq <= `NoStop;	//不暂停流水线
					end else begin
						div_op1 <= `ZeroWord;
						div_op2 <= `ZeroWord;
						div_start_o <= `DivStop;
						signed_div_o <= 1'b0;
						div_annul_i <= 1'b1;
						div_stallreq <= `NoStop;
					end
				end
				`EXE_DIVU_OP:begin
					if (ready_i == `DivResNotReady) begin
						div_op1 <= reg1_i;
						div_op2 <= reg2_i;
						div_start_o <= `DivStart;
						signed_div_o <= 1'b0;
						div_annul_i <= 1'b0;
						div_stallreq <= `Stop;		//暂停流水线
					end else if (ready_i == `DivResReady) begin
						div_op1 <= reg1_i;
						div_op2 <= reg2_i;
						div_start_o <= `DivStop;
						signed_div_o <= 1'b0;
						div_annul_i <= 1'b1;
						div_stallreq <= `NoStop;	//不暂停流水线
					end else begin
						div_op1 <= `ZeroWord;
						div_op2 <= `ZeroWord;
						div_start_o <= `DivStop;
						signed_div_o <= 1'b0;
						div_annul_i <= 1'b1;
						div_stallreq <= `NoStop;
					end
				end
				default:begin
				end
			endcase
		end
	end
	
	always @(*) begin
		//暂停流水线
		stallreq <= div_stallreq;
	end

	always @ (*) begin
		wd_o <= wd_i;	 

		if(ex_is_in_delayslot)
			wreg_o <= `WriteDisable;
		else	 	
			wreg_o <= wreg_i;

		case (alusel_i) 
			`EXE_RES_LOGIC:wdata_o <= logicout;
			`EXE_RES_SHIFT:wdata_o <= shiftout;
			`EXE_RES_MOV:wdata_o <= movout;
			`EXE_RES_ARITHMETIC:wdata_o <= result_arithmetic[31:0];
			`EXE_RES_MUL:begin
				hi_o <= mulout[63:32];
				lo_o <= mulout[31:0];
				we_o <= `WriteEnable;
			end
			`EXE_RES_DIV:begin
				hi_o <= result_i[63:32];
				lo_o <= result_i[31:0];
				if (stallreq)
					we_o <= `WriteDisable;
				else
					we_o <= `WriteEnable;
			end
			`EXE_RES_JUMP:wdata_o <= wdata_o;
			`EXE_RES_CALL:wdata_o <= reg2_i;
			`EXE_RES_RET:wdata_o <= wdata_o;
			`EXE_RES_LOOP:wdata_o <= reg2_i - 1;
			//`EXE_RES_LOAD_STORE:wdata_o <= 32'h0;
		default:wdata_o <= `ZeroWord;
		endcase
	end

	always @(*) begin
		if (rst == `RstEnable) begin
			cp0_reg_data_o <= `ZeroWord;
			cp0_reg_waddr_o <= 5'b00000;
			cp0_reg_we_o <= `WriteDisable;
		end else if (aluop_i == `EXE_MTC_OP) begin
			cp0_reg_waddr_o <= inst_i[51:47];
			cp0_reg_we_o <= `WriteEnable;
			cp0_reg_data_o <= reg1_i;
		end else begin
			cp0_reg_data_o <= `ZeroWord;
			cp0_reg_waddr_o <= 5'b00000;
			cp0_reg_we_o <= `WriteDisable;
		end
	end
endmodule