defmodule Phoenix.SessionProcess.LiveViewIntegrationTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.LiveView, as: SessionLV
  alias Phoenix.SessionProcess.SessionId

  @pubsub_name TestIntegrationPubSub

  # Test session process that broadcasts state changes
  defmodule IntegrationSessionProcess do
    use Phoenix.SessionProcess, :process

    @impl true
    def init(init_arg) do
      {:ok, init_arg}
    end

    @impl true
    def handle_call(:get_state, _from, state) do
      {:reply, {:ok, state}, state}
    end

    @impl true
    def handle_call({:set_count, count}, _from, state) do
      new_state = %{state | count: count}
      # Broadcast to LiveViews
      broadcast_state_change(new_state)
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call(:increment, _from, state) do
      new_state = %{state | count: state.count + 1}
      broadcast_state_change(new_state)
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_cast({:set_user, user}, state) do
      new_state = %{state | user: user}
      broadcast_state_change(new_state)
      {:noreply, new_state}
    end
  end

  # Mock LiveView process
  defmodule MockLiveView do
    def start_link(session_id, pubsub, parent) do
      Task.start_link(fn ->
        # Simulate LiveView mount
        socket = %{assigns: %{}}

        case SessionLV.mount_session(socket, session_id, pubsub) do
          {:ok, socket, initial_state} ->
            send(parent, {:mounted, self(), initial_state})

            # Simulate LiveView message handling loop
            receive_loop(socket, parent)

          {:error, reason} ->
            send(parent, {:mount_error, reason})
        end
      end)
    end

    defp receive_loop(socket, parent) do
      receive do
        {:session_state_change, new_state} ->
          send(parent, {:state_updated, self(), new_state})
          receive_loop(socket, parent)

        :terminate ->
          SessionLV.unmount_session(socket)
          send(parent, {:terminated, self()})
      end
    end
  end

  setup do
    # Start PubSub
    case start_supervised({Phoenix.PubSub, name: @pubsub_name}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Configure pubsub for broadcast_state_change
    Application.put_env(:phoenix_session_process, :pubsub, @pubsub_name)

    on_exit(fn ->
      Application.delete_env(:phoenix_session_process, :pubsub)
    end)

    %{pubsub: @pubsub_name}
  end

  describe "full mount flow" do
    test "LiveView mounts and gets initial state", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      # Start session with initial state
      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "alice", count: 0})

      # Mount LiveView
      socket = %{assigns: %{}}
      {:ok, socket, initial_state} = SessionLV.mount_session(socket, session_id, pubsub)

      # Verify initial state
      assert initial_state == %{user: "alice", count: 0}
      assert socket.assigns.__session_id__ == session_id

      # Cleanup
      SessionLV.unmount_session(socket)
      SessionProcess.terminate(session_id)
    end

    test "LiveView receives state change broadcasts", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "bob", count: 0})

      # Mount LiveView
      socket = %{assigns: %{}}
      {:ok, _socket, _state} = SessionLV.mount_session(socket, session_id, pubsub)

      # Update session state
      SessionProcess.call(session_id, {:set_count, 42})

      # LiveView should receive broadcast
      assert_receive {:session_state_change, %{user: "bob", count: 42}}, 200

      # Update again
      SessionProcess.call(session_id, :increment)

      assert_receive {:session_state_change, %{user: "bob", count: 43}}, 200

      # Cleanup
      SessionProcess.terminate(session_id)
    end

    test "state is properly updated in LiveView", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "charlie", count: 5})

      socket = %{assigns: %{}}
      {:ok, _socket, initial_state} = SessionLV.mount_session(socket, session_id, pubsub)

      # Initial state
      assert initial_state.count == 5

      # Increment multiple times
      SessionProcess.call(session_id, :increment)
      assert_receive {:session_state_change, state1}, 200
      assert state1.count == 6

      SessionProcess.call(session_id, :increment)
      assert_receive {:session_state_change, state2}, 200
      assert state2.count == 7

      # Cleanup
      SessionProcess.terminate(session_id)
    end
  end

  describe "multiple LiveViews" do
    test "multiple LiveView processes subscribe to same session", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "shared", count: 0})

      # Start multiple mock LiveViews
      {:ok, lv1} = MockLiveView.start_link(session_id, pubsub, self())
      {:ok, lv2} = MockLiveView.start_link(session_id, pubsub, self())

      # Wait for both to mount
      assert_receive {:mounted, ^lv1, %{user: "shared", count: 0}}, 200
      assert_receive {:mounted, ^lv2, %{user: "shared", count: 0}}, 200

      # Update session state
      SessionProcess.call(session_id, {:set_count, 99})

      # Both LiveViews should receive the update
      assert_receive {:state_updated, ^lv1, %{count: 99}}, 200
      assert_receive {:state_updated, ^lv2, %{count: 99}}, 200

      # Cleanup
      send(lv1, :terminate)
      send(lv2, :terminate)
      assert_receive {:terminated, ^lv1}, 200
      assert_receive {:terminated, ^lv2}, 200
      SessionProcess.terminate(session_id)
    end

    test "all receive broadcasts when session updates", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "broadcast", count: 1})

      # Start 3 LiveViews
      {:ok, lv1} = MockLiveView.start_link(session_id, pubsub, self())
      {:ok, lv2} = MockLiveView.start_link(session_id, pubsub, self())
      {:ok, lv3} = MockLiveView.start_link(session_id, pubsub, self())

      # Wait for mounts
      assert_receive {:mounted, ^lv1, _}, 200
      assert_receive {:mounted, ^lv2, _}, 200
      assert_receive {:mounted, ^lv3, _}, 200

      # Multiple updates
      SessionProcess.cast(session_id, {:set_user, "updated"})
      SessionProcess.call(session_id, :increment)

      # All should receive both updates
      for lv <- [lv1, lv2, lv3] do
        assert_receive {:state_updated, ^lv, %{user: "updated", count: 1}}, 200
        assert_receive {:state_updated, ^lv, %{user: "updated", count: 2}}, 200
      end

      # Cleanup
      for lv <- [lv1, lv2, lv3], do: send(lv, :terminate)
      SessionProcess.terminate(session_id)
    end

    test "each can unmount independently", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "test", count: 0})

      # Start 2 LiveViews
      {:ok, lv1} = MockLiveView.start_link(session_id, pubsub, self())
      {:ok, lv2} = MockLiveView.start_link(session_id, pubsub, self())

      assert_receive {:mounted, ^lv1, _}, 200
      assert_receive {:mounted, ^lv2, _}, 200

      # Unmount lv1
      send(lv1, :terminate)
      assert_receive {:terminated, ^lv1}, 200

      # Update state
      SessionProcess.call(session_id, :increment)

      # Only lv2 should receive
      assert_receive {:state_updated, ^lv2, %{count: 1}}, 200
      refute_receive {:state_updated, ^lv1, _}, 100

      # Cleanup
      send(lv2, :terminate)
      SessionProcess.terminate(session_id)
    end
  end

  describe "error scenarios" do
    test "mount with non-existent session", %{pubsub: pubsub} do
      socket = %{assigns: %{}}
      nonexistent = "nonexistent_session_xyz"

      result = SessionLV.mount_session(socket, nonexistent, pubsub)

      assert {:error, {:session_not_found, ^nonexistent}} = result
    end

    test "session terminates while LiveView is mounted", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "temp", count: 0})

      # Mount LiveView
      socket = %{assigns: %{}}
      {:ok, _socket, _state} = SessionLV.mount_session(socket, session_id, pubsub)

      # Terminate session
      SessionProcess.terminate(session_id)

      # Future broadcasts won't arrive (session is gone)
      # But unmounting should still work gracefully
      # This is fine - LiveView will handle the missing session
      assert SessionProcess.started?(session_id) == false
    end

    test "unmount without mount", %{pubsub: _pubsub} do
      socket = %{assigns: %{}}

      # Should not crash
      result = SessionLV.unmount_session(socket)
      assert result == :ok
    end

    test "dispatch to non-existent session" do
      result = SessionLV.dispatch("nonexistent_session", :some_message)

      assert {:error, {:session_not_found, "nonexistent_session"}} = result
    end

    test "dispatch_async to non-existent session" do
      result = SessionLV.dispatch_async("nonexistent_session", :some_message)

      assert {:error, {:session_not_found, "nonexistent_session"}} = result
    end
  end

  describe "distributed simulation (PubSub)" do
    test "PubSub works across 'nodes' (simulated with processes)", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{
          user: "distributed",
          count: 0
        })

      # Simulate different "nodes" by using different processes
      parent = self()

      # "Node 1" - subscribes to session
      node1 =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(pubsub, "session:#{session_id}:state")
          send(parent, {:node1_ready, self()})

          receive do
            {:session_state_change, state} ->
              send(parent, {:node1_received, state})
          end
        end)

      # "Node 2" - also subscribes
      node2 =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(pubsub, "session:#{session_id}:state")
          send(parent, {:node2_ready, self()})

          receive do
            {:session_state_change, state} ->
              send(parent, {:node2_received, state})
          end
        end)

      # Wait for both "nodes" to be ready
      assert_receive {:node1_ready, ^node1}, 200
      assert_receive {:node2_ready, ^node2}, 200

      # "Node 3" updates the session
      SessionProcess.call(session_id, {:set_count, 777})

      # Both "nodes" should receive the broadcast
      assert_receive {:node1_received, %{count: 777}}, 200
      assert_receive {:node2_received, %{count: 777}}, 200

      # Cleanup
      SessionProcess.terminate(session_id)
    end

    test "broadcasts are topic-isolated between sessions", %{pubsub: pubsub} do
      session1 = SessionId.generate_unique_session_id()
      session2 = SessionId.generate_unique_session_id()

      {:ok, _} =
        SessionProcess.start(session1, IntegrationSessionProcess, %{user: "user1", count: 0})

      {:ok, _} =
        SessionProcess.start(session2, IntegrationSessionProcess, %{user: "user2", count: 0})

      # Subscribe to both sessions
      Phoenix.PubSub.subscribe(pubsub, "session:#{session1}:state")
      Phoenix.PubSub.subscribe(pubsub, "session:#{session2}:state")

      # Update session1
      SessionProcess.call(session1, {:set_count, 100})

      # Should only receive update for session1
      assert_receive {:session_state_change, %{user: "user1", count: 100}}, 200

      # Update session2
      SessionProcess.call(session2, {:set_count, 200})

      # Should only receive update for session2
      assert_receive {:session_state_change, %{user: "user2", count: 200}}, 200

      # No extra messages
      refute_receive {:session_state_change, _}, 100

      # Cleanup
      SessionProcess.terminate(session1)
      SessionProcess.terminate(session2)
    end
  end

  describe "real-world workflow simulation" do
    test "complete user session workflow", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      # 1. User logs in - session starts
      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{
          user: nil,
          count: 0,
          last_activity: nil
        })

      # 2. Dashboard LiveView mounts
      {:ok, dashboard} = MockLiveView.start_link(session_id, pubsub, self())
      assert_receive {:mounted, ^dashboard, initial_state}, 200

      assert initial_state.user == nil
      assert initial_state.count == 0

      # 3. User authenticates - update session
      SessionProcess.cast(session_id, {:set_user, "john_doe"})

      # 4. Dashboard receives update
      assert_receive {:state_updated, ^dashboard, %{user: "john_doe"}}, 200

      # 5. Another LiveView (navbar) mounts
      {:ok, navbar} = MockLiveView.start_link(session_id, pubsub, self())
      assert_receive {:mounted, ^navbar, navbar_state}, 200

      assert navbar_state.user == "john_doe"

      # 6. User performs action - both LiveViews should update
      SessionProcess.call(session_id, :increment)

      assert_receive {:state_updated, ^dashboard, state1}, 200
      assert_receive {:state_updated, ^navbar, state2}, 200

      # Both received the same update
      assert state1.count == 1
      assert state2.count == 1

      # 7. User navigates away from dashboard
      send(dashboard, :terminate)
      assert_receive {:terminated, ^dashboard}, 200

      # 8. Update should still reach navbar
      SessionProcess.call(session_id, :increment)

      assert_receive {:state_updated, ^navbar, %{count: 2}}, 200

      # Only navbar message (dashboard unsubscribed)
      refute_receive {:state_updated, ^dashboard, _}, 100

      # 9. User logs out - clean up
      send(navbar, :terminate)
      assert_receive {:terminated, ^navbar}, 200
      SessionProcess.terminate(session_id)

      assert SessionProcess.started?(session_id) == false
    end
  end

  describe "performance and concurrency" do
    test "handles rapid state updates", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "fast", count: 0})

      # Subscribe
      Phoenix.PubSub.subscribe(pubsub, "session:#{session_id}:state")

      # Rapid updates
      for i <- 1..10 do
        SessionProcess.call(session_id, {:set_count, i})
      end

      # Should receive all updates (may arrive in batches)
      # Wait for final state
      assert_receive {:session_state_change, %{count: 10}}, 500

      # Cleanup
      SessionProcess.terminate(session_id)
    end

    test "handles many concurrent subscribers", %{pubsub: pubsub} do
      session_id = SessionId.generate_unique_session_id()

      {:ok, _pid} =
        SessionProcess.start(session_id, IntegrationSessionProcess, %{user: "popular", count: 0})

      # Start 10 subscribers
      parent = self()

      subscribers =
        for i <- 1..10 do
          spawn_link(fn ->
            Phoenix.PubSub.subscribe(pubsub, "session:#{session_id}:state")
            send(parent, {:ready, i})

            receive do
              {:session_state_change, state} ->
                send(parent, {:received, i, state})
            end
          end)
        end

      # Wait for all to be ready
      for i <- 1..10 do
        assert_receive {:ready, ^i}, 200
      end

      # Broadcast update
      SessionProcess.call(session_id, {:set_count, 999})

      # All should receive
      for i <- 1..10 do
        assert_receive {:received, ^i, %{count: 999}}, 200
      end

      # Cleanup
      for pid <- subscribers do
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end

      SessionProcess.terminate(session_id)
    end
  end
end
