// @ts-nocheck
import Transport from "@ledgerhq/hw-transport";

/**
 * iOS Bluetooth Transport implementation
 */
export default class TransportBLEiOS extends Transport {

  /**
   * SwiftTransport lives in the `global` scope and gets injected by the Swift Native Module
   */
  private transport: SwiftTransport;

  constructor() {
    super();
    this.transport = SwiftTransport.create();
  }

  /**
   * communicate with a BLE transport
   */
  async exchange(apdu: Buffer): Promise<Buffer> {
    const response = await this.promisify(this.transport.exchange(apdu));
    return Buffer.from(response)
  }

  promisify(callback) {
    return new Promise((resolve, reject) => {
        callback(function(response) {
            resolve(response)
        })
    })
  }
}
