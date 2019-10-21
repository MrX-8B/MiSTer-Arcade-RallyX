/**************************************************************
	FPGA New Rally-X (Video Part)
***************************************************************/
module NRX_VIDEO
(
	input				 VCLKx4,		// 24.976MHz

	input  [8:0]		HPOSi,
	input  [8:0]		VPOSi,
	output				PCLK,
	output reg [7:0]	POUT,

	input					CPUCLK,
	input	 [15:0]		CPUADDR,
	input	 [7:0]		CPUDI,
	output [7:0]		CPUDO,
	input					CPUME,
	input					CPUWE,
	output				CPUDT,

	input					ROMCL,
	input  [15:0]		ROMAD,
	input  [7:0]		ROMDT,
	input					ROMEN
);

wire [8:0] HPOS = HPOSi+2;
wire [8:0] VPOS = VPOSi+(HPOSi>=504);

//-----------------------------------------
//  Clock generators
//-----------------------------------------
reg VCLKx2;
always @( posedge VCLKx4 ) begin
	VCLKx2 <= ~VCLKx2;
end

reg VCLK;
always @( posedge VCLKx2 ) begin
	VCLK   <= ~VCLK;
end

//-----------------------------------------
//  BG scroll registers
//-----------------------------------------
reg [7:0] BGHSCR;
reg [7:0] BGVSCR;

always @ ( posedge CPUCLK ) begin
	if ( ( CPUADDR == 16'hA130 ) & CPUME & CPUWE ) begin
		BGHSCR <= CPUDI-3;
	end
	if ( ( CPUADDR == 16'hA140 ) & CPUME & CPUWE ) begin
		BGVSCR <= CPUDI;
	end
end


//-----------------------------------------
//  HV
//-----------------------------------------
wire [8:0] BGHPOS = HPOS + { 1'b0, BGHSCR };
wire [8:0] BGVPOS = VPOS + { 1'b0, BGVSCR };

wire oHB = ( HPOS > 288 ) ? 1 : 0;
wire oVB = ( VPOS > 224 ) ? 1 : 0;


//----------------------------------------
//  VideoRAM Scanner
//----------------------------------------
wire				BF	= ( HPOS >= 224 );
wire	[8:0]		HP = ( BF ? HPOS : BGHPOS );
wire	[8:0]		VP = ( BF ? VPOS : BGVPOS ) + 9'd16;

wire	[10:0]	SPRAADRS;
wire	[3:0]		ARAMADRS;

reg	[10:0]	VRAMADRS;
always @ ( HPOS ) begin
	VRAMADRS <= oHB ? 
		SPRAADRS :
		BF ? { 1'b0, VP[7:3], 2'b00, HP[5:3] } : { 1'b1, VP[7:3], HP[7:3] };
end

wire	[7:0]		CHRC;
wire	[7:0]		ATTR;
wire	[7:0]		ARDT;

wire	[7:0]		V0DO, V1DO;

wire				CEV0	= ( ( CPUADDR[15:12] == 4'b1000 ) & (~CPUADDR[11]) ) & CPUME;
wire				CEV1	= ( ( CPUADDR[15:12] == 4'b1000 ) &   CPUADDR[11]  ) & CPUME;
wire				CEAT  = (   CPUADDR[15:4]  == 12'b1010_0000_0000         ) & CPUME;

wire	[7:0]		DTV0	= CEV0 ? V0DO : 8'h00;
wire	[7:0]		DTV1	= CEV1 ? V1DO : 8'h00;

assign			CPUDO = DTV0 | DTV1;
assign			CPUDT = ( ~CPUWE ) & ( CEV0 | CEV1 );

GDPRAM #(11,8) vram0( VCLKx4, VRAMADRS, CHRC, CPUCLK, CPUADDR[10:0], ( CPUWE & CEV0 ), CPUDI, V0DO );  
GDPRAM #(11,8)	vram1( VCLKx4, VRAMADRS, ATTR, CPUCLK, CPUADDR[10:0], ( CPUWE & CEV1 ), CPUDI, V1DO );  
GDPRAM #(4,8)	aram0( VCLKx4, ARAMADRS, ARDT, CPUCLK, CPUADDR[3:0],  ( CPUWE & CEAT ), CPUDI );

wire				BGF = ATTR[5];


//----------------------------------------
//  BG/Sprite chip data reader
//----------------------------------------
wire				BGFX = ATTR[6];
wire	[2:0]		BGFY = { ATTR[7], ATTR[7], ATTR[7] };

wire	[11:0]	SPCHRADR;
wire	[11:0]	CHRA = oHB ? SPCHRADR : { CHRC, ( HP[2] ^ BGFX ), ( VP[2:0] ^ BGFY ) };

wire	[7:0]		CHRO;
DLROM #(12,8)  chrrom(VCLKx4,CHRA,CHRO, ROMCL,ROMAD,ROMDT,ROMEN & (ROMAD[15:12]==4'h8));


//----------------------------------------
//  Rader-dot chip ROM
//----------------------------------------
wire  [7:0] 	DROMAD;
wire  [7:0] 	DROMDT;
DLROM #(8,8)	dotrom(VCLKx4,DROMAD,DROMDT, ROMCL,ROMAD,ROMDT,ROMEN & (ROMAD[15:8]==8'h90));


//----------------------------------------
//  BG/FG scanline generator
//----------------------------------------
wire [5:0] BGPL = ATTR[5:0];
reg  [7:0] BGCOL;

always @ ( posedge VCLK ) begin
	case ( HP[1:0]^{2{BGFX}} )
		2'b00: BGCOL <= { BGPL, CHRO[4], CHRO[0] };
		2'b01: BGCOL <= { BGPL, CHRO[5], CHRO[1] };
		2'b10: BGCOL <= { BGPL, CHRO[6], CHRO[2] };
		2'b11: BGCOL <= { BGPL, CHRO[7], CHRO[3] };
	endcase
end	


//----------------------------------------
//  Sprite Engine
//----------------------------------------
wire [8:0] SPCOL;
NRX_SPRITE speng( VCLKx4, oHB, HPOS, VPOS, SPRAADRS, { ATTR, CHRC }, ARAMADRS, ARDT, SPCHRADR, CHRO, DROMAD, DROMDT, SPCOL );


//----------------------------------------
//  Color mixer
//----------------------------------------
wire bBGOPAQUE = ( ( BF | BGF ) & (~SPCOL[8]) );
wire bSPTRANSP = ( SPCOL[1:0] == 2'b00 );

wire	[7:0]		OUTCOL = ( bBGOPAQUE | bSPTRANSP ) ? BGCOL : SPCOL[7:0];
wire	[3:0]		CLUT;
DLROM #(8,4)	colorlt(~VCLKx4,OUTCOL,CLUT, ROMCL,ROMAD,ROMDT,ROMEN & (ROMAD[15:8]==8'h92));

wire	[4:0]		PALA = SPCOL[8] ? SPCOL[4:0] : { 1'b0, CLUT };
wire	[7:0]		PALO;
DLROM #(5,8)	palette(VCLKx4,PALA,PALO,  ROMCL,ROMAD,ROMDT,ROMEN & (ROMAD[15:5]=={8'h93,3'b000}));


//----------------------------------------
//  Color output
//----------------------------------------
always @ ( posedge PCLK ) POUT <= PALO;
assign PCLK = VCLK;


endmodule
