-module(chat_server).

-define(TCP_OPTIONS, [binary, {active,false}, {reuseaddr, true}]).

-compile(export_all).

-record(server, {lsocket, acceptor, clients}).
-record(clients, {socket, name, client_pid}).

start(Port) ->
  spawn(?MODULE, init, [Port]).

init(Port) ->
  {ok, ListenSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
  A = spawn_link(?MODULE, accept, [ListenSocket, self()]),
  server_loop(#server{lsocket = ListenSocket, acceptor = A, clients=[]}).

accept(ListenSocket, ServerPID) ->
  {ok, AcceptSocket} = gen_tcp:accept(ListenSocket),
  spawn(?MODULE, client, [AcceptSocket, ServerPID]),
  accept(ListenSocket, ServerPID).

client(AcceptSocket, ServerPID) ->
  gen_tcp:send(AcceptSocket, "\nWelcome to TelChat!\nTo send a message, type the message and press Enter\n"),
  gen_tcp:send(AcceptSocket, "To send a private message, type PVT 'name' (quotes included) followed by message\n"),
  gen_tcp:send(AcceptSocket, "Enjoy!\n\n"),
  gen_tcp:send(AcceptSocket, "Enter a username.\r\n"),
  {ok, N} = gen_tcp:recv(AcceptSocket,0),
  [Name] = string:tokens(binary_to_list(N),"\r\n"),
  New_Client = #clients{socket = AcceptSocket, name = Name, client_pid = self()},
  ServerPID ! {"New Client", New_Client},
  client_loop(New_Client, ServerPID).

client_loop(Client, ServerPID) ->
  {ok, Msg} = gen_tcp:recv(Client#clients.socket, 0),
  ServerPID ! {"New Message", Msg, Client},
  client_loop(Client, ServerPID).

server_loop(State = #server{clients = ClientList}) ->
  receive
    {"New Client", New_Client} ->
      case [X||X <- ClientList , X#clients.name =:= New_Client#clients.name] of
        [] ->
          NewClientList = [New_Client|ClientList],
          broadcast(NewClientList,["~s has joined the conversation\n", New_Client#clients.name]),
          server_loop(State#server{clients = NewClientList});
        _List ->
          gen_tcp:send(New_Client#clients.socket, "Sorry, name is already in use.\n"),
          gen_tcp:close(New_Client#clients.socket),
          server_loop(State#server{clients = ClientList})
      end;

      {"New Message", Msg = <<"bye", _/binary>>, Client} ->
        broadcast(ClientList,["<<~s>> ~s\n", Client#clients.name, Msg]),
        broadcast(ClientList,["~s has left the conversation\n", Client#clients.name]),
        gen_tcp:close(Client#clients.socket),
        server_loop(State#server{clients = lists:delete(Client, ClientList)});

        {"New Message", <<"PVT ", T/binary>>, Client} ->
          [N|T1] = string:tokens(binary_to_list(T), "'"),
          Msg = string:concat("(private)", T1),
          case [X||X <- ClientList , X#clients.name =:= N] of
            [] ->
              gen_tcp:send(Client#clients.socket, "That username doesn't exist!\n"),
              server_loop(State);
            _List ->
              PVTClientList = [X || X <- ClientList, X#clients.name =:= N orelse X#clients.name =:= Client#clients.name],
              broadcast(PVTClientList,["<<~s>> ~s", Client#clients.name, Msg]),
              server_loop(State)
            end;

        {"New Message", Msg, Client} ->
          broadcast(ClientList,["<<~s>> ~s", Client#clients.name, Msg]),
          server_loop(State)

  end.

broadcast(ClientList, [Format|Arguments]) ->
  P = lists:flatten(io_lib:fwrite(Format, Arguments)),
  lists:foreach(fun (#clients{socket=Sock}) ->  gen_tcp:send(Sock,P)  end, ClientList).
