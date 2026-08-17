//
//  INDSMPTransport.h
//  eNDS
//
//  Multijugador local del DS. melonDS NO expone esto por `MPInterface`: eso
//  es cosa del frontend Qt y `src/net/` ni se compila aquí. `Wifi.cpp` llama
//  a `Platform::MP_*` (Platform.h:299-307) y esas nueve funciones las pone el
//  frontend — nosotros. Así que todo esto vive en la app y el submódulo
//  `Vendor/melonDS` se queda intacto, que es lo que sostiene el
//  "unmodified upstream melonDS" de BUILDING.md.
//
//  El contrato lo fija `net/LocalMP.cpp`, que es la implementación de
//  referencia. Lo que hay que respetar sí o sí:
//
//   - `recvReplies` escribe la respuesta de cada cliente en
//     `out[(aid - 1) * kReplyStride]`, con hueco fijo. Pasarse de ahí pisa
//     la respuesta del siguiente.
//   - Se descarta todo paquete con `timestamp < now - kStaleWindow`: son
//     microsegundos de tiempo emulado, no de reloj de pared.
//   - Las recepciones bloquean hasta `kRecvTimeoutMs`. Se llaman DESDE EL
//     HILO DE EMULACIÓN, así que ese timeout es tiempo que el juego pasa
//     congelado: es el precio del lockstep y el motivo de que esto sea duro.
//
//  Un transporte no sabe nada de red. El de verdad (MultipeerConnectivity)
//  llegará detrás de esta misma interfaz; el primero es un loopback en
//  proceso para poder validar la máquina de estados sin red de por medio.
//

#ifndef INDS_MP_TRANSPORT_H
#define INDS_MP_TRANSPORT_H

#include <cstdint>

namespace eNDS {

/// Hueco por AID en el búfer de `recvReplies`. Lo fija el core, no nosotros.
constexpr int kReplyStride = 1024;
/// Antigüedad máxima de un paquete, en microsegundos de tiempo emulado.
constexpr uint64_t kStaleWindow = 32;
/// Lo que melonDS usa por defecto. Cada milisegundo aquí es un milisegundo
/// que el emulador pasa parado.
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
    /// -1 si el host se ha ido; si no, longitud del paquete (0 = nada).
    virtual int recvHostPacket(int inst, uint8_t *out, uint64_t *timestamp) = 0;
    /// Máscara de los AID que contestaron.
    virtual uint16_t recvReplies(int inst, uint8_t *out, uint64_t timestamp, uint16_t aidmask) = 0;
};

/// Sin transporte instalado los hooks devuelven 0, que es exactamente lo que
/// hacían cuando eran stubs: sin multijugador la app se comporta igual y no
/// aparece ni una API de red en el binario.
MPTransport *currentTransport();
void setCurrentTransport(MPTransport *transport);

/// El core pasa la instancia de `MelonDSCoreBridge` como `userdata`
/// (`MelonDSCoreBridge.mm`, `make_unique<NDS>(args, (__bridge void *)self)`),
/// así que hay un core por bridge y dos partidas en el mismo proceso no
/// necesitan ningún desenredo. Esto traduce ese puntero al índice que espera
/// el transporte.
int instanceForUserdata(void *userdata);
void registerInstance(void *userdata, int inst);
void unregisterInstance(void *userdata);

}

#endif // INDS_MP_TRANSPORT_H
