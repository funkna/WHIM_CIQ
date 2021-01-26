using Toybox.Ant;
using Toybox.System;
using Toybox.WatchUi;

enum {
    STATE_UNACQUIRED,
    STATE_CLOSED,
    STATE_SEARCHING,
    STATE_PAIRED
}

class WhimChannel extends Ant.GenericChannel
{
    const DEVICE_NUMBER = 0;
    const DEVICE_TYPE = 23;
    const TRANS_TYPE = 0;
    const MSG_PERIOD = 8192;
    const FREQUENCY = 66;

    var state = STATE_UNACQUIRED;

    function initialize() {
        try {
            // Get the channel
            var chanAssign = new Ant.ChannelAssignment(Ant.CHANNEL_TYPE_RX_NOT_TX, Ant.NETWORK_PUBLIC);
            GenericChannel.initialize(method(:onMessage), chanAssign);

            // Channel has been acquired, set to STATE_CLOSED
            state = STATE_CLOSED;

            // Set the configuration
            var deviceConfig = new Ant.DeviceConfig( {
                :deviceNumber => DEVICE_NUMBER,
                :deviceType => DEVICE_TYPE,
                :transmissionType => TRANS_TYPE,
                :messagePeriod => MSG_PERIOD,
                :radioFrequency => FREQUENCY } );
            GenericChannel.setDeviceConfig(deviceConfig);

            System.println( "Channel initialized" );

        } catch ( ex instanceof UnableToAcquireChannelException ) {
            System.println( "ERROR: Unable to acquire channel" );
        } catch ( ex ) {
            System.println( "ERROR: Unexpected exception in Channel.initialize(): " + ex );
        }
    }

    function open() {
        // Attempt to open channel and handle accordingly
        if( GenericChannel.open() ) {
            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Channel opened" );
            state = STATE_SEARCHING;
        }
        else {
            System.println( "ERROR: Unable to open channel" );
        }
    }

    function close() {
        state = STATE_CLOSED;
        GenericChannel.close();
        System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Channel closed" );
    }

    function release() {
        // Release channel if one has been acquired
        if( state != STATE_UNACQUIRED ) {
            GenericChannel.release();
        }
    }

    function getState() {
        return state;
    }

    function onMessage( msg ) {
        try {
            var payload = msg.getPayload();

            if (Ant.MSG_ID_BROADCAST_DATA == msg.messageId) {

                // Handle Data Page 1
                if (payload[0] == 0x01) {
                    System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Data Page 1 Received!" );

                    if (STATE_SEARCHING == state) {
                        state = STATE_PAIRED;
                        channelManager.openSearchChannel();
                        // Swich to sensor details view - TODO: Update UI for multisensor
                        System.println(GenericChannel.getDeviceConfig().deviceNumber + ": View switched!");
                        var view = new SensorDetailsView();
                        WatchUi.switchToView(view, new SensorDetailsDelegate(view), WatchUi.SLIDE_IMMEDIATE);
                    }

                    if (impacts != payload[1]) {
                        System.println( GenericChannel.getDeviceConfig().deviceNumber + ": New Data!" );
                        impacts = payload[1];
                        WatchUi.requestUpdate();
                    }
                }
                else {
                    System.println(GenericChannel.getDeviceConfig().deviceNumber + ": Unrecognized data page received.");
                }

            } else if( Ant.MSG_ID_CHANNEL_RESPONSE_EVENT == msg.messageId ) {
                if( Ant.MSG_ID_RF_EVENT == payload[0] ) {
                    var eventCode = payload[1];

                    switch( eventCode ) {

                        case Ant.MSG_CODE_EVENT_RX_FAIL:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: RX_FAIL" );
                            break;

                        case Ant.MSG_CODE_EVENT_TX:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: EVENT_TX" );
                            break;

                        case Ant.MSG_CODE_EVENT_TRANSFER_TX_COMPLETED:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: TRANSFER_TX_COMPLETED" );
                            break;

                        case Ant.MSG_CODE_EVENT_TRANSFER_TX_FAILED:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: TRANSFER_TX_FAILED" );
                            sendResetDataCommand();
                            break;

                        case Ant.MSG_CODE_EVENT_CHANNEL_CLOSED:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: CHANNEL_CLOSED" );
                            checkChannelClosure();
                            resetDeviceConfig();
                            channelManager.openSearchChannel();
                            break;

                        case Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: RX_FAIL_GO_TO_SEARCH" );
                            state = STATE_SEARCHING;
                            resetDeviceConfig();
                            // Switch to sensor pair view - TODO: Update UI for multisensor
                            var view = new SensorPairView();
                            WatchUi.switchToView(view, new SensorPairDelegate(view), WatchUi.SLIDE_IMMEDIATE);
                            break;

                        case Ant.MSG_CODE_EVENT_RX_SEARCH_TIMEOUT:
                            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Response event: RX_SEARCH_TIMEOUT" );
                            state = STATE_CLOSED; // Channel will automatically close
                            break;

                        default:
                            handleUnexpectedAntEvent( eventCode );
                            break;
                    }
                }
            }
        } catch ( ex ) {
            state = STATE_CLOSED;
            GenericChannel.close();
            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": ERROR: Unexpected exception in Channel.onMessage()", ex );
            WatchUi.requestUpdate();
        }
    }

    function checkChannelClosure() {
        if( STATE_CLOSED != state ) {
            System.println( GenericChannel.getDeviceConfig().deviceNumber + ": ERROR: Channel closed unexpectedly" );
            state = STATE_CLOSED;
            WatchUi.requestUpdate();
        }
    }

    function handleUnexpectedAntEvent( eventCode ) {
        System.println( GenericChannel.getDeviceConfig().deviceNumber + ": Unhandled ANT event: " + eventCode );
        WatchUi.requestUpdate();
    }

    function resetDeviceConfig() {
        var deviceConfig = new Ant.DeviceConfig( {
            :deviceNumber => DEVICE_NUMBER,
            :deviceType => DEVICE_TYPE,
            :transmissionType => TRANS_TYPE,
            :messagePeriod => MSG_PERIOD,
            :radioFrequency => FREQUENCY } );
        GenericChannel.setDeviceConfig(deviceConfig);
    }

    function sendResetDataCommand() {
        var data = new[8];
        data[0] = 0x10;
        data[1] = 0x00;
        data[2] = 0xFF;
        data[3] = 0xFF;
        data[4] = 0xFF;
        data[5] = 0xFF;
        data[6] = 0xFF;
        data[7] = 0xFF;

        var message = new Ant.Message();
        message.setPayload(data);
        GenericChannel.sendAcknowledge(message);
    }

}
