module iRobot(Clock, Reset, FunctionSelect, En, Confirm, Duration, setTime, DirtySpot, Battery, LED, Vacuum, Mop, Sanitize, Brake);

    // Main Inputs
    input Clock;
    input Reset; 				// Resets counter & FSM
    input En; 					// Power on signal 
    input Confirm; 				// To load customized duration to counter
    input [1:0] FunctionSelect;			// User select function; Vacuum = 0, Sanitize = 1, Mop = 2, ComboMode = 3
    input [5:0] Duration;			// Custom set duration, assume each bit = 1 min
    input [10:0] setTime;			// Custom set starting time

    // Main outputs
    output LED, Vacuum, Mop, Sanitize, Brake;
	 
    // Internal Inputs
    input wire DirtySpot;						// Signal from dirty spot detector and battery status
    input wire Battery;							// Signal indicating battery status
    wire [0:3] FunctionOutput; 						// Output from 2-to-4 decoder to run selected cleaning function
    wire [10:0] realTime; 						// Real-time seconds
    wire goTime; 							// Signal indicating real-time match
    wire [5:0] CountDuration; 						// To store main cleaning count
    wire RunSpot; 							// Signal to FSM to perform dirty spot cleaning
    wire RunDurationVSM, RunDurationV, RunDurationS, RunDurationM; 	// Signal to FSM to run selected cleaning function

	// Instantiate 2-to-4 Decoder for FunctionSelect
	Decoder2to4 decoder(FunctionSelect, En, FunctionOutput);

	// Instantiate Real-time Checker to start main counter when set time is met
	RealTimeChecker checktime(Clock, En, Reset, setTime, realTime, goTime);

	// Instantiate main cleaning counter to run cleaning function for set duration
	CleaningCounter counter(Clock, Reset, Battery, goTime, Confirm, Duration, CountDuration);
			 
	// Run spot cleaning for a fixed duration when dirty spot detected
	DirtySpotModule dirtyspot(Clock, DirtySpot, RunSpot);

	// Outputs assignment to FSM to run selected cleaning function
	assign RunDurationV = (FunctionOutput == 4'b1000 && goTime && |CountDuration); 	 // Signal to Run Vacuum
	assign RunDurationS = (FunctionOutput == 4'b0100 && goTime && |CountDuration); 	 // Signal to run sanitize
	assign RunDurationM = (FunctionOutput == 4'b0010 && goTime && |CountDuration); 	 // Signal to Run Mop
	assign RunDurationVSM = (FunctionOutput == 4'b0001 && goTime && |CountDuration); // Signal to Run ComboMode

	// FSM for controlling the cleaning functions, battery interrupt, and spot cleaning
	FSMclean FSM(Clock, Reset, RunDurationV, RunDurationS, RunDurationM, RunDurationVSM, RunSpot, Battery, LED, Vacuum, Mop, Sanitize, Brake);

endmodule


module RealTimeChecker(Clock, En, Reset, setTime, realTime, goTime);
    input Clock;         		// Clock input
    input En;      			// Enable/power on signal
    input Reset;			// To reset goTime signal
    input [10:0] setTime; 		// Set time in mins
    output reg [10:0] realTime = 0; 	// Register to emulate real-time mins
    output reg goTime = 0; 		// Signal to main counter when set time is met

	 always @(posedge Clock)
		 if (En)
			 begin
				realTime <= realTime + 1; // Emulates real time counting when iRobot is powered on

			  	// Check if the set time matches the real time
				if (setTime == realTime)
					goTime <= 1; // Set goTime high when set time matches real time
					
				// Check if realTime reaches the count value of 10110100000 (1440 min), then reset back to 0
				if (realTime == 11'b10110100000)
					realTime <= 0;
				 
				 if (Reset)
					goTime <= 0;
			 end
			 
endmodule


module CleaningCounter(Clock, Reset, Battery, goTime, Confirm, Duration, CountDuration);
	input Clock, Reset, Battery, goTime, Confirm;
	input [5:0] Duration;
	output reg [5:0] CountDuration;
	
		always@(posedge Reset, posedge Clock)
		if (Reset)
			CountDuration <= 0;
		else if (Confirm)
			CountDuration <= Duration;
		else if (goTime && CountDuration && Battery > 0)
			CountDuration <= CountDuration - 1;	
			
endmodule
  
  
module DirtySpotModule(Clock, DirtySpot, RunSpot);
	input Clock, DirtySpot;
	reg [1:0] SpotDuration;
	output RunSpot;
		
		 // When dirty spot is detected, stay on spot for 3mins
		 always @(posedge Clock) begin
		 if (DirtySpot)
			SpotDuration <= 3; 
		 else if(SpotDuration > 0)
			SpotDuration <= SpotDuration - 1;
		 else
			SpotDuration <= 0;
		end
  
  assign RunSpot = |SpotDuration; // This signal will be assigned to FSM
  
endmodule


module Decoder2to4(FunctionSelect, En, FunctionOutput);
	input En;
	input [1:0] FunctionSelect; 				// User can select 4 functions
	output reg [0:3] FunctionOutput;			// This output determines which cleaning function to perform

	always @(FunctionSelect, En) begin
	
		if (En ==0)
			FunctionOutput = 4'b0000;
		
		else
			case (FunctionSelect)
				0 : FunctionOutput = 4'b1000;	// Vacuum
				1 : FunctionOutput = 4'b0100;	// Sanitize
				2 : FunctionOutput = 4'b0010;	// Mop
				3 : FunctionOutput = 4'b0001;	// Vacuum, sanitize, mop
			endcase
	end
	
endmodule


module FSMclean(Clock, Reset, RunVacuum, RunSanitize, RunMop, RunCombo, RunSpot, Battery, LED, Vacuum, Mop, Sanitize, Brake);
  input Clock, Reset, RunVacuum, RunSanitize, RunMop, RunCombo, RunSpot, Battery; 
  output reg LED, Vacuum, Mop, Sanitize, Brake; 

    // Define states
    parameter [2:0] IDLE_STATE = 3'b000,
                    VACUUM_STATE = 3'b001,
                    SANITIZE_STATE = 3'b010,
                    MOP_STATE = 3'b011,
                    COMBO_STATE = 3'b100,
                    STOP_STATE = 3'b101;

    // Define the state register and next state
    reg [2:0] present_state, next_state;

    // Combinational logic for state transitions and outputs
    always @* begin
        case (present_state)

            // No outputs are functioning
            IDLE_STATE: begin
                LED = 0;
                Vacuum = 0;
                Mop = 0;
                Sanitize = 0;
                Brake = 0;

                // If battery is high and cleaning function selected, transition to selected cleaning state
                if (Battery) begin
                    if (RunCombo) next_state = COMBO_STATE;
                    else if (RunVacuum) next_state = VACUUM_STATE;
                    else if (RunSanitize) next_state = SANITIZE_STATE;
                    else if (RunMop) next_state = MOP_STATE;
                    else next_state = IDLE_STATE;
                end else
                    // If battery is low, stop all functions and light LED
                    next_state = STOP_STATE;
            end

            // Vacuum output is on
            VACUUM_STATE: begin
                LED = 0;
                Vacuum = 1;
                Mop = 0;
                Sanitize = 0;
					 
		// Activate brake to stay on spot longer for cleaning if dirty spot is detected
                if (RunSpot) Brake = 1;
                else Brake = 0;

                if (!Battery) next_state = STOP_STATE;
                else if (!RunVacuum) next_state = IDLE_STATE; 
            end

            // Sanitize output is on
            SANITIZE_STATE: begin
                LED = 0;
                Vacuum = 0;
                Mop = 0;
                Sanitize = 1;

		// Activate brake to stay on spot longer for cleaning if dirty spot is detected
                if (RunSpot) Brake = 1;
                else Brake = 0;

                if (!Battery) next_state = STOP_STATE;
                else if (!RunSanitize) next_state = IDLE_STATE; 
            end

            // Mop output is on
            MOP_STATE: begin
                LED = 0;
                Vacuum = 0;
                Mop = 1;
                Sanitize = 0;

		// Activate brake to stay on spot longer for cleaning if dirty spot is detected
                if (RunSpot) Brake = 1;
                else Brake = 0;

                if (!Battery) next_state = STOP_STATE;
                else if (!RunMop) next_state = IDLE_STATE; 
            end

            // All outputs (Combo) are on
            COMBO_STATE: begin
                LED = 0;
                Vacuum = 1;
                Mop = 1;
                Sanitize = 1;

		// Activate brake to stay on spot longer for cleaning if dirty spot is detected
                if (RunSpot) Brake = 1;
                else Brake = 0;

                if (!Battery) next_state = STOP_STATE;
                else if (!RunCombo) next_state = IDLE_STATE; 
            end

            // All outputs are off, stop state
            STOP_STATE: begin
                LED = 1;
                Vacuum = 0;
                Mop = 0;
                Sanitize = 0;
                Brake = 0;

                if (Battery) begin
                    if (RunCombo) next_state = COMBO_STATE;
                    else if (RunVacuum) next_state = VACUUM_STATE;
                    else if (RunSanitize) next_state = SANITIZE_STATE;
                    else if (RunMop) next_state = MOP_STATE;
                    else next_state = IDLE_STATE;
                end else
                    next_state = STOP_STATE;
            end

            default: next_state = IDLE_STATE;
        endcase
    end

    // Sequential logic for state update
    always @(posedge Clock, posedge Reset) begin
        if (Reset)
            present_state <= IDLE_STATE;
        else
            present_state <= next_state;
    end

endmodule
