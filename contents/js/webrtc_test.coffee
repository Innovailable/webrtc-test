q = require('q')
ride = require('ride')

query_string = require('query-string')
uuid = require('node-uuid')
require('string-format')

$ = jquery = require('jquery')
palava = require("palava-client")

current_url = () ->
  return window.location.href.split('?')[0]


# monkey patch some logging into palava peers

class palava.RemotePeer extends palava.RemotePeer

  constructor: (id, status, room, offers) ->
    @start = Date.now()

    @messages = []
    @states = []

    super(id, status, room, offers)

    ride(@distributor, 'send').before (data) =>
      @messages.push {
        time: @time()
        direction: 'out'
        message: data
      }

    @distributor.channel.on 'message', (data) =>
      @messages.push {
        time: @time()
        direction: 'in'
        message: data
      }

    ride(@peerConnection, 'oniceconnectionstatechange').before (event) =>
      @states.push {
        time: @time()
        type: 'ice'
        state: event.target.iceConnectionState
      }

    @peerConnection.onsignalingstatechange = (event) =>
      @states.push {
        time: @time()
        type: 'signaling'
        state: event.target.signalingState
      }


  time: () ->
    return Date.now() - @start


# the different test methods (echo, inviting and being invited)

class MultiUserTest

  name: "invite"


  constructor: (@test) ->
    @frontend = @test.frontend


  invite_url: () ->
    return "{0}?r={1}".format(@test.options.url_base, @test.room_id)


  finish: () ->
    @frontend.clear()
    @frontend.title("Peer still testing")
    @frontend.prompt("Please wait for your peer to finish testing.")

    return @test.peer_p.then (peer) =>
      peer.sendMessage {
        type: 'test_finish'
      }
    .then () =>
      return @finish_d.promise


  wait_connect: () ->
    return @test.peer_p.then (peer) =>
      return @start_d.promise.timeout(5000, "Unable to test with peer")


  init_peer: (peer) ->
    @start_d= q.defer()
    @finish_d= q.defer()

    peer.on 'message', (data) =>
      console.log 'message!'
      console.log data

      if data.type == 'test_start'
        @start_d.resolve()

      if data.type == 'test_finish'
        @finish_d.resolve()

    peer.sendMessage {
      type: 'test_start'
    }


class InvitingTest extends MultiUserTest

  start: () ->
    html = 'Please ask the person you want to test with to visit the following page:<br />{0}'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    defer = q.defer()

    @frontend.add_button "Done", () ->
      defer.resolve()

    return defer.promise


  wait: () ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br />{0}'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    return @wait_connect()


class InvitedTest extends MultiUserTest

  start: () ->
    q()


  wait: () ->
    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt('Waiting for other user. Please make sure that the other user did not abort the test.')

    console.log 'invited waiting'

    return @wait_connect()


class EchoTest

  name: "echo"


  constructor: (@test) ->
    @frontend = @test.frontend


  start: () ->
    q()


  wait: (cb) ->
    @frontend.clear()
    @frontend.title("Contacting Echo Server")
    @frontend.prompt("Waiting for connection with echo server ...")

    return q($.ajax({
      url: @test.options.echo_server
      type: 'POST'
      data: {
        room: @room_id
      }
    })).then () =>
      return @test.peer_p.timeout(10000)
    .fail () =>
      throw Error("Error inviting echo server")



  finish: (cb) ->
    q()


# the actual test code

class WebRtcTest

  constructor: (@frontend, options={}) ->
    @result = {
      time: Date.now()
      a: {}
    }

    @errors = []

    @options = $.extend({
      url_base:     current_url()
      echo_server:  null
      stun:         'stun:stun.palava.tv'
      signaling:    'wss://machine.palava.tv'
    }, options)

    @start()


  # helper

  add_error: (text) ->
    @errors.push(text)


  fatal_error: (exception) ->
    text = exception.message

    console.log exception
    console.log exception.stack

    @add_error(text)

    @frontend.clear()
    @frontend.title("Error")
    @frontend.prompt("Sorry, a fatal error occured: " + text)

    defer = q.defer()

    @frontend.add_button "OK", () =>
      defer.resolve()

    return defer.promise


  # start control flow of test

  start: () ->
    # actual flow

    q.when =>
      @test_webrtc()
    .then =>
      @test_method()
    .then =>
      @test_session()
    .then =>
      @method.start()
    .then =>
      @test_local()
    .then =>
      @test_join()
    .then =>
      @method.wait()
    .then =>
      @test_remote()
    .then =>
      @test_data()
    .then =>
      @method.finish()
    .then =>
      @get_peer_data()
    .fail (err) =>
      @fatal_error(err)
    .then =>
      @report()
    .done()


  test_webrtc: () ->
    # check whether WebRTC is even available

    if palava.browser.checkForWebrtcError()
      throw Error("Your browser does not seem to support WebRTC")


  test_method: () ->
    # which method to use?

    query = query_string.parse(location.search)

    # we are invited

    if query.r?
      @room_id = query.r

      @method = new InvitedTest(@)

      return q()

    # no echo server and not invited ... we have to invite

    if not @options.echo_server
      @method = new InvitingTest(@)
      return q()

    # ask user

    @frontend.clear()
    @frontend.title("Test Setup")
    @frontend.prompt("Do you want to test with another person or using the echo server?")

    defer = q.defer()

    @frontend.add_button "Invite User", () =>
      @method = new InvitingTest(@)
      defer.resolve()

    @frontend.add_button "Echo Server", () =>
      @method = new EchoTest(@)
      defer.resolve()

    return defer.promise


  # internal

  test_session: () ->
    @result.method = @method.name

    if not @room_id?
      @room_id = uuid.v4()

    if typeof @options.signaling == 'string'
      channel = new palava.WebSocketChannel(@options.signaling)
    else
      channel = @options.signaling

    @session = new palava.Session
      roomId: @room_id
      channel: channel
      dataChannels:
        test:
          ordered: true

    # peer handling

    peer_d = q.defer()
    @peer_p = peer_d.promise

    remote_d = q.defer()
    @remote_p = remote_d.promise

    data_channel_d = q.defer()
    @data_channel_p = data_channel_d.promise

    data_data_d = q.defer()
    @data_data_p = data_data_d.promise

    use_peer = (peer) =>
      if not @peer_p.isPending()
        console.log 'already resolved!'
        return

      peer_d.resolve(peer)

      @method.init_peer?(peer)

      peer.on 'stream_ready', (stream) =>
        console.log stream
        console.log peer
        remote_d.resolve(peer.getStream())

      peer.on 'stream_error', () =>
        remote_d.fail("Stream error")

      peer.on 'channel_ready', (name, channel) =>
        if name != 'test'
          return

        data_channel_d.resolve()

        test_msg = "hello world"

        channel.send(test_msg)

        channel.on 'message', (data) =>
          if data == test_msg
            data_data_d.resolve()
          else
            data_data_d.fail("Data channel data mismatch")

    @session.on 'peer_joined', (peer) =>
      use_peer(peer)

    # room handling

    room_d = q.defer()
    @room_p = room_d.promise

    @session.on 'room_joined', (room) ->
      room_d.resolve(room)

      for id, peer of room.peers
        if not peer.isLocal()
          use_peer(peer)
          break

    # local stream handling

    local_d = q.defer()
    @local_p = local_d.promise

    @session.on 'local_stream_ready', (stream) =>
      local_d.resolve(stream)

    @session.on 'local_stream_error', () =>
      local_d.reject(new Error("Local stream error"))

    q()


  test_join: () ->
    @frontend.clear()
    @frontend.title("Joining")
    @frontend.prompt("Joining test room ...")

    @session.room.join()

    return @room_p.timeout(10000, "Unable to join test room")


  # test streams and data channels

  test_av: (type, res) ->
    test_video = () =>
      # video

      @frontend.clear_input()
      @frontend.prompt("Do you see an image?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        res.audio = true
        defer.resolve()

      @frontend.add_button "No", () =>
        res.audio = false
        @add_error("No {0} video".format(type))
        defer.resolve()

      return defer.promise

    test_audio = () =>
      # audio

      @frontend.clear_input()
      @frontend.prompt("Do you hear audio?")

      defer = q.defer()

      @frontend.add_button "Yes", () =>
        res.video = true
        defer.resolve()

      @frontend.add_button "No", () =>
        res.video = false
        @add_error("No {0} audio".format(type))
        defer.resolve()

      return defer.promise

    return test_video().then(test_audio)


  test_local: () ->
    @frontend.clear()
    @frontend.title("Local Media Access")
    @frontend.prompt("Your browser should ask you whether you want to grant this site access to your camera and microphone")

    @session.init
      identity: new palava.Identity
        userMediaConfig:
          audio: true
          video: true
        name: "Tester"
      options:
        stun: @options.stun
        joinTimeout: 500

    res = @result.a.local = {}

    return @local_p.then (stream) =>
      res.stream = true
      @frontend.video(stream)
      return @test_av("local", res)
    .fail (err) =>
      res.stream = false
      console.log err
      throw Error("Local media access denied")


  test_remote: () ->
    @frontend.clear()
    @frontend.title("Remote Media")
    @frontend.prompt("Waiting for remote media to arrive ...")

    res = @result.a.remote = {}

    return @remote_p.timeout(30000).then (stream) =>
      res.stream = true
      @frontend.video(stream)
      return @test_av("remote", res)
    .fail (err) =>
      res.stream = false
      throw Error("Unable to receive remote data")


  test_data: () ->
    @frontend.clear()
    @frontend.title("Data Channel")
    @frontend.prompt("Waiting for data channel to arrive ...")

    res = @result.a.data = {
      channel: false
      data: false
    }

    return @data_channel_p.timeout(5000, "Unable to open data channel").then () =>
      @frontend.prompt("Waiting for data channel data to arrive ...")
      res.channel = true
      return @data_data_p.timeout(5000, "Data channel did not receive data")
    .then () =>
      res.data = true
      return q()
    .fail (err) =>
      @add_error(err.message)
      return q()



  get_peer_data: () ->
    return @peer_p.then (peer) =>
      @result.signaling = peer.messages
      @result.a.states = peer.states


  # reporting

  report: () ->
    @peer_p.then (peer) =>
      console.log 'result'
      console.log @result

    @session.destroy()

    @frontend.clear()
    @frontend.title("Test complete")

    html = "<div>Thanks for testing. Please press the button below to report the results to the developers.</div>"

    if @errors.length
      error_list = $('<ul>')

      for error in @errors
        error_list.append($('<li>').text(error))

      html += error_list.html()
    else
      html += "<div>No errors detected</div>"

    @frontend.prompt_html(html)

    @frontend.add_button "Send report", () =>
      console.log "Reporting ... someday"

      # TODO

      @frontend.clear()
      @frontend.title("Thanks!")
      @frontend.prompt("Thanks for sending the report! Well  ... actually reporting does not work, yet. But thanks anyway.")


module.exports =
  WebRtcTest: WebRtcTest
