%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Definition of external functions of module IO:
%
% Note: the Prolog term '$stream'('$inoutstream'(In,Out)) represents a handle
% for a stream that is both readable (on In) and writable (on Out)
% Otherwise, handles are represented by Prolog terms of the form '$stream'(N).
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%:- module(prim_io,
%	  [handle_eq/2,
%          prim_stdin/1,prim_stdout/1,prim_stderr/1,prim_openFile/3,
%	   prim_hClose/2,prim_hFlush/2,prim_hIsEOF/2,prim_hSeek/4,
%	   prim_hWaitForInput/5,prim_hWaitForInputs/5,
%          prim_hWaitForInputsOrMsg/5,
%	   prim_hGetChar/2,prim_hPutChar/3,
%          prim_hIsReadable/2,prim_hIsWritable/2, prim_hIsTerminalDevice/2]).

:- (current_module(prologbasics) -> true ; use_module('../prologbasics')).
:- (current_module(basics)       -> true ; use_module('../basics')).
:- (current_module(prim_ports)   -> true ; ensure_loaded(prim_ports)). % to implement IO.prim_hWaitForInputsOrMsg

?- block prim_hWaitForInput(?,?,?,-,?).
prim_hWaitForInput(Hdl,TO,partcall(1,exec_hWaitForInput,[TO,Hdl]),E,E).
?- block exec_hWaitForInput(?,?,?,?,-,?).
exec_hWaitForInput(RStream,RTO,World,'$io'(B),E0,E) :-
	exec_hWaitForInputs([RStream],RTO,World,'$io'(N),E0,E1),
	(N=0 -> B='Prelude.True' ; B='Prelude.False'),
	!, E1=E.

?- block prim_hWaitForInputs(?,?,?,-,?).
prim_hWaitForInputs(H,T,partcall(1,exec_hWaitForInputs,[T,H]),E,E).
?- block exec_hWaitForInputs(?,?,?,?,-,?).
exec_hWaitForInputs(RStreams,RTO,_,'$io'(N),E0,E) :-
	user:derefAll(RStreams,Streams),
	selectInstreams(Streams,InStreams),
	user:derefRoot(RTO,TimeOut),
	waitForInputDataOnStreams(InStreams,TimeOut,N),
	!, E0=E.

selectInstreams([],[]).
selectInstreams(['$stream'('$inoutstream'(In,_))|Streams],[In|InStreams]) :- !,
	selectInstreams(Streams,InStreams).
selectInstreams([Stream|Streams],[Stream|InStreams]) :-
	selectInstreams(Streams,InStreams).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% choice on a stream and an external port message stream:
?- block prim_hWaitForInputsOrMsg(?,?,?,-,?).
prim_hWaitForInputsOrMsg(H,M,partcall(1,exec_hWaitForInputsOrMsg,[M,H]),E,E).

?- block exec_hWaitForInputsOrMsg(?,-,?,?,?,?),
         exec_hWaitForInputsOrMsg(?,?,?,?,-,?).
exec_hWaitForInputsOrMsg(Handles,share(M),World,Result,E0,E) :-
        !,
	get_mutable(V,M),
	(V='$eval'(R) % external message stream has been already evaluated
	 -> E0=E, Result='$io'('Prelude.Right'(R))
	  ; exec_hWaitForInputsOrMsg(Handles,V,World,CResult,E0,E),
	    (CResult='$io'('Prelude.Left'(_))
  	     -> Result=CResult
	      ; CResult='$io'('Prelude.Right'(S)),
	        (compileWithSharing(variable) -> user:propagateShare(S,TResult)
		                               ; S=TResult),
	        Result='$io'('Prelude.Right'(TResult)),
	        update_mutable('$eval'(TResult),M))).
exec_hWaitForInputsOrMsg(_,[M|Ms],_,'$io'('Prelude.Right'([M|Ms])),E0,E) :-
	!, E0=E. % stream already evaluated
exec_hWaitForInputsOrMsg(RHandles,[],_,'$io'('Prelude.Left'(N)),E0,E) :- !,
	% message stream is empty, so anything must be received from the handles.
	user:derefAll(RHandles,Handles),
	selectInstreams(Handles,InStreams),
	waitForInputDataOnStreams(InStreams,-1,N),
	!, E0=E.
exec_hWaitForInputsOrMsg(Handles,'Ports.basicServerLoop'(Port),World,
			Result,E0,E) :-
        Port='Ports.internalPort'(_,_,PNr,_),
	checkIncomingPortStreams(PNr,InPortStream,OutPortStream),
	!,
	readStreamUntilEndOfTerm(InPortStream,MsgString),
	(parse_received_message(InPortStream,OutPortStream,MsgString,Msg)
	 -> ifTracePort((write(user_error,'TRACEPORTS: Received message: '),
		         write(user_error,Msg), nl(user_error))),
	    Result='$io'('Prelude.Right'([Msg|'Ports.basicServerLoop'(Port)])), E0=E
	  ; write(user_error,'ERROR: Illegal message received (ignored): '),
	    putChars(user_error,MsgString), nl(user_error),
	    exec_hWaitForInputsOrMsg(Handles,'Ports.basicServerLoop'(Port),World,
	                                   Result,E0,E)),
	!.
exec_hWaitForInputsOrMsg(RHandles,'Ports.basicServerLoop'(Port),World,Result,E0,E):-
	user:derefAll(RHandles,Handles),
	selectInstreams(Handles,InStreams),
        Port='Ports.internalPort'(_,_,PNr,Socket),
	waitForSocketOrInputStreams(Socket,Client,InPortStream,OutPortStream,
				    InStreams,Index),
	(Client=no
	 -> % there is input on Handles:
	    Result='$io'('Prelude.Left'(Index)), E0=E
	  ; % there is a client connection:
	    ifTracePort((write(user_error,'TRACEPORTS: Connection to client: '),
		         write(user_error,Client), nl(user_error))),
	    (readPortMessage(PNr,InPortStream,OutPortStream,MsgString)
	     -> (parse_received_message(InPortStream,OutPortStream,MsgString,Msg)
	         -> ifTracePort((write(user_error,'TRACEPORTS: Received message: '),
		                 write(user_error,Msg), nl(user_error))),
		    Result='$io'('Prelude.Right'([Msg|'Ports.basicServerLoop'(Port)])), E0=E
	          ; write(user_error,'ERROR: Illegal message received (ignored): '),
		    putChars(user_error,MsgString), nl(user_error),
		    exec_hWaitForInputsOrMsg(Handles,
                                 'Ports.basicServerLoop'(Port),World,Result,E0,E))
	      ; % try reading next message:
		exec_hWaitForInputsOrMsg(Handles,
		                 'Ports.basicServerLoop'(Port),World,Result,E0,E))),
	!.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
