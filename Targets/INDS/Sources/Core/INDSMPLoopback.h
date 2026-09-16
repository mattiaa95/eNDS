//
//  INDSMPLoopback.h
//  eNDS
//
//  In-process multiplayer transport: several core instances inside the same
//  app talking to each other over in-memory queues. It never touches the
//  network.
//
//  It exists for two reasons, and the second is the important one:
//
//   1. It is the reference the real transport is measured against. If two
//      games do not stay in sync here, where latency is zero and no packet
//      is ever lost, they will not stay in sync over Wi-Fi.
//   2. It isolates the lockstep state machine from the network. Mixing the
//      two from the start, with no way to say which of them was failing, is
//      where the link-cable bugs in our GBA emulator came from.
//

#ifndef INDS_MP_LOOPBACK_H
#define INDS_MP_LOOPBACK_H

#include "INDSMPTransport.h"

#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <vector>

namespace eNDS {

class MPLoopback : public MPTransport {
public:
    static constexpr int kMaxInstances = 16;

    void begin(int inst) override;
    void end(int inst) override;

    int sendPacket(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int recvPacket(int inst, uint8_t *out, uint64_t *timestamp) override;
    int sendCmd(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int sendReply(int inst, const uint8_t *data, int len, uint64_t timestamp, uint16_t aid) override;
    int sendAck(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int recvHostPacket(int inst, uint8_t *out, uint64_t *timestamp) override;
    uint16_t recvReplies(int inst, uint8_t *out, uint64_t timestamp, uint16_t aidmask) override;

#if DEBUG
    /// Assert-based check of the contract above. It runs by itself on load
    /// in Debug: this is a state machine with clocks and bit masks, and
    /// breaking it silently is exactly what cannot be allowed to happen.
    static void selfCheck();
#endif

private:
    struct Packet {
        std::vector<uint8_t> data;
        uint64_t timestamp = 0;
        int sender = -1;
        uint16_t aid = 0;
        bool fromHost = false;
    };

    struct Queue {
        std::deque<Packet> packets;   // normal traffic + the host's CMD frames
        std::deque<Packet> replies;   // the clients' replies
        bool connected = false;
    };

    /// Per-queue cap. A peer that never drains (not polling, or gone quiet)
    /// must not grow its queues forever; past this the oldest frame is
    /// dropped, and anything that old is stale by the time it could be read.
    /// `LocalMP` bounds the same thing with a 64 KB ring per FIFO.
    static constexpr size_t kMaxQueueDepth = 64;

    /// Drops the packet into everyone's queue except the sender's.
    int broadcast(int from, const uint8_t *data, int len, uint64_t timestamp,
                  bool toReplyQueue, bool fromHost, uint16_t aid);
    /// Pops the first packet that has not gone stale, waiting up to
    /// `kRecvTimeoutMs`.
    int receive(int inst, uint8_t *out, uint64_t *timestamp, bool hostOnly);

    std::mutex _lock;
    std::condition_variable _arrived;
    Queue _queues[kMaxInstances];
    int _lastHostID = -1;
};

}

#endif // INDS_MP_LOOPBACK_H
