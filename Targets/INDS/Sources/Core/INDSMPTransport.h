//
//  INDSMPTransport.h
//  eNDS
//
//  Local DS multiplayer. melonDS does NOT expose this through `MPInterface`:
//  that belongs to the Qt frontend and `src/net/` is not even compiled here.
//  `Wifi.cpp` calls `Platform::MP_*` (Platform.h:299-307) and those nine
//  functions are the frontend's job — ours. So all of this lives in the app
//  and the `Vendor/melonDS` submodule stays untouched, which is what keeps
//  BUILDING.md's "unmodified upstream melonDS" true.
//
//  The contract is set by `net/LocalMP.cpp`, the reference implementation.
//  What has to be respected, no exceptions:
//
//   - `recvReplies` writes each client's reply at
//     `out[(aid - 1) * kReplyStride]`, a fixed slot. Writing past it
//     overwrites the next client's reply.
//   - Every packet with `timestamp < now - kStaleWindow` is dropped: those
//     are microseconds of emulated time, not wall clock.
//   - Receives block for up to `kRecvTimeoutMs`. They are called FROM THE
//     EMULATION THREAD, so that timeout is time the game spends frozen: it
//     is the price of lockstep and the reason this is hard.
//
//  A transport knows nothing about networking. The real one
//  (MultipeerConnectivity) will land behind this same interface; the first
//  one is an in-process loopback so the state machine can be validated with
//  no network in the way.
//

#ifndef INDS_MP_TRANSPORT_H
#define INDS_MP_TRANSPORT_H

#include <cstdint>

namespace eNDS {

/// Per-AID slot in the `recvReplies` buffer. The core sets it, not us.
constexpr int kReplyStride = 1024;
/// Maximum packet age, in microseconds of emulated time.
constexpr uint64_t kStaleWindow = 32;
/// What melonDS uses by default. Every millisecond here is a millisecond
/// the emulator spends stalled.
constexpr int kRecvTimeoutMs = 25;

class MPTransport {
public:
    virtual ~MPTransport() = default;

    virtual void begin(int inst) = 0;
    virtual void end(int inst) = 0;

    virtual int sendPacket(int inst, const uint8_t *data, int len, uint64_t timestamp) = 0;
    virtual int recvPacket(int inst, uint8_t *out, uint64_t *timestamp) = 0;
    virtual int sendCmd(int inst, const uint8_t *data, int len, uint64_t timestamp) = 0;
    virtual int sendReply(int inst, const uint8_t *data, int len, uint64_t timestamp, uint16_t aid) = 0;
    virtual int sendAck(int inst, const uint8_t *data, int len, uint64_t timestamp) = 0;
    /// -1 if the host is gone; otherwise the packet length (0 = nothing).
    virtual int recvHostPacket(int inst, uint8_t *out, uint64_t *timestamp) = 0;
    /// Mask of the AIDs that replied.
    virtual uint16_t recvReplies(int inst, uint8_t *out, uint64_t timestamp, uint16_t aidmask) = 0;
};

/// With no transport installed the hooks return 0, exactly what they did as
/// stubs: without multiplayer the app behaves the same and not one networking
/// API shows up in the binary.
MPTransport *currentTransport();
void setCurrentTransport(MPTransport *transport);

/// The core carries the `MelonDSCoreBridge` instance as `userdata`
/// (`MelonDSCoreBridge.mm`, `make_unique<NDS>(args, (__bridge void *)self)`),
/// so there is one core per bridge and two games in the same process need no
/// untangling. This maps that pointer to the index the transport expects.
int instanceForUserdata(void *userdata);
void registerInstance(void *userdata, int inst);
void unregisterInstance(void *userdata);

}

#endif // INDS_MP_TRANSPORT_H
