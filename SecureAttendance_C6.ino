#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLEAdvertising.h>

#include <mbedtls/gcm.h>
#include <esp_system.h>
#include <esp_bt.h>

// ======================================================
// CẤU HÌNH
// ======================================================

// Tên thiết bị dùng chung.
// Không chứa tên phòng để tránh lộ thông tin phòng.
#define DEVICE_NAME "SecureAttendance_C6"

// Token thay đổi mỗi 30 giây
const unsigned long TOKEN_INTERVAL = 30000;

// ======================================================
// DEVICE ID
//
// Mỗi ESP32 phải có DEVICE_ID riêng.
//
// Ví dụ:
// Phòng 301 -> ID riêng
// Phòng 302 -> ID riêng
// Phòng 303 -> ID riêng
//
// KHÔNG đưa ROOM_301 / ROOM_302 trực tiếp vào BLE.
// ======================================================

const uint32_t DEVICE_ID = 0xA1B2C3D4;


// ======================================================
// AES-128 KEY
//
// Chỉ dùng cho prototype/test.
// Không hard-code key trong hệ thống thực tế.
// ======================================================

const uint8_t AES_KEY[16] = {
  0x21, 0x47, 0x93, 0xA8,
  0x15, 0x62, 0xCE, 0x39,
  0x74, 0xB1, 0x08, 0xF5,
  0xD2, 0x6A, 0x40, 0x9C
};


// ======================================================
// BIẾN
// ======================================================

unsigned long previousMillis = 0;

// Counter bắt đầu bằng giá trị ngẫu nhiên
// để tránh quay lại 0 sau mỗi lần khởi động.
uint32_t counter;


// ======================================================
// KHAI BÁO HÀM
// ======================================================

void updateBeacon();
void printHex(const uint8_t *data, size_t len);


// ======================================================
// SETUP
// ======================================================

void setup() {

  Serial.begin(115200);

  delay(1000);

  Serial.println();
  Serial.println("========================================");
  Serial.println(" SMART ATTENDANCE - ESP32-C6");
  Serial.println(" AES-128-GCM SECURE BLE");
  Serial.println(" DYNAMIC TOKEN - 30 SECONDS");
  Serial.println("========================================");


  // ----------------------------------------------------
  // Khởi tạo counter ngẫu nhiên
  // ----------------------------------------------------

  esp_fill_random(
    &counter,
    sizeof(counter)
  );

  Serial.print("[INFO] Initial Counter: ");
  Serial.println(counter);


  // ----------------------------------------------------
  // Khởi tạo BLE
  // ----------------------------------------------------

  BLEDevice::init(
    DEVICE_NAME
  );


  // ----------------------------------------------------
  // Cấu hình công suất BLE
  //
  // ESP32-C6 hỗ trợ mức công suất cao hơn
  // các ESP32 đời cũ.
  //
  // P20 = +20 dBm theo tài liệu ESP32-C6.
  // ----------------------------------------------------

  esp_err_t powerResult =
    esp_ble_tx_power_set_enhanced(
      ESP_BLE_ENHANCED_PWR_TYPE_ADV,
      0,
      ESP_PWR_LVL_P20
    );


  if (powerResult == ESP_OK) {

    Serial.println(
      "[BLE] Advertising TX Power: P20"
    );

    Serial.println(
      "[BLE] Requested TX Power: +20 dBm"
    );

  } else {

    Serial.print(
      "[BLE] TX Power configuration failed. Error: "
    );

    Serial.println(
      powerResult
    );
  }


  // ----------------------------------------------------
  // Tạo advertising đầu tiên
  // ----------------------------------------------------

  updateBeacon();

  previousMillis = millis();
}


// ======================================================
// LOOP
// ======================================================

void loop() {

  unsigned long currentMillis =
    millis();


  // ----------------------------------------------------
  // Cứ 30 giây tạo token mới
  // ----------------------------------------------------

  if (
    currentMillis - previousMillis
    >= TOKEN_INTERVAL
  ) {

    previousMillis =
      currentMillis;

    counter++;

    updateBeacon();
  }


  delay(10);
}


// ======================================================
// UPDATE BEACON
// ======================================================

void updateBeacon() {

  // ----------------------------------------------------
  // Lấy BLE Advertising
  // ----------------------------------------------------

  BLEAdvertising *pAdvertising =
    BLEDevice::getAdvertising();


  // Dừng advertising cũ
  pAdvertising->stop();

  delay(100);


  // ====================================================
  // 1. PLAINTEXT
  //
  // Chỉ mã hóa DEVICE_ID.
  //
  // Counter đã nằm trong Nonce.
  //
  // 4 byte DEVICE_ID
  // ====================================================

  uint8_t plaintext[4];


  memcpy(
    plaintext,
    &DEVICE_ID,
    sizeof(DEVICE_ID)
  );


  // ====================================================
  // 2. NONCE
  //
  // 12 byte:
  //
  // 4 byte DEVICE_ID
  // 4 byte COUNTER
  // 4 byte RANDOM
  //
  // Tổng = 96 bit
  // ====================================================

  uint8_t nonce[12];


  memcpy(
    nonce,
    &DEVICE_ID,
    4
  );


  memcpy(
    nonce + 4,
    &counter,
    4
  );


  uint32_t randomPart;


  esp_fill_random(
    &randomPart,
    sizeof(randomPart)
  );


  memcpy(
    nonce + 8,
    &randomPart,
    4
  );


  // ====================================================
  // 3. AES-GCM OUTPUT
  // ====================================================

  uint8_t ciphertext[4];

  // Tag 8 byte thay vì 4 byte ở bản cũ
  uint8_t tag[8];


  // ====================================================
  // 4. KHỞI TẠO AES-GCM
  // ====================================================

  mbedtls_gcm_context gcm;

  mbedtls_gcm_init(
    &gcm
  );


  // ====================================================
  // 5. NẠP AES-128 KEY
  // ====================================================

  int result =
    mbedtls_gcm_setkey(
      &gcm,
      MBEDTLS_CIPHER_ID_AES,
      AES_KEY,
      128
    );


  if (result != 0) {

    Serial.println(
      "[ERROR] AES key initialization failed"
    );

    mbedtls_gcm_free(
      &gcm
    );

    return;
  }


  // ====================================================
  // 6. AES-128-GCM ENCRYPTION
  // ====================================================

  result =
    mbedtls_gcm_crypt_and_tag(

      &gcm,

      MBEDTLS_GCM_ENCRYPT,

      sizeof(plaintext),

      nonce,
      sizeof(nonce),

      nullptr,
      0,

      plaintext,

      ciphertext,

      sizeof(tag),

      tag
    );


  mbedtls_gcm_free(
    &gcm
  );


  // ====================================================
  // 7. KIỂM TRA
  // ====================================================

  if (result != 0) {

    Serial.println(
      "[ERROR] AES-GCM encryption failed"
    );

    return;
  }


  // ====================================================
  // 8. MANUFACTURER DATA
  //
  // Cấu trúc:
  //
  // Byte 0-1   : Company ID demo
  // Byte 2-13  : Nonce 12 byte
  // Byte 14-17 : Ciphertext 4 byte
  // Byte 18-25 : Authentication Tag 8 byte
  //
  // Tổng = 26 byte
  //
  // Lưu ý: BLE Legacy Advertising tối đa 31 byte.
  // 26 byte Manufacturer Data + 2 byte AD header
  // + 3 byte Flags = đúng 31 byte.
  // ====================================================

  uint8_t manufacturerData[26];


  // Company ID demo
  manufacturerData[0] = 0xFF;
  manufacturerData[1] = 0xFF;


  // Nonce
  memcpy(
    manufacturerData + 2,
    nonce,
    12
  );


  // Ciphertext
  memcpy(
    manufacturerData + 14,
    ciphertext,
    4
  );


  // Authentication Tag
  memcpy(
    manufacturerData + 18,
    tag,
    8
  );


  // ====================================================
  // 9. BINARY DATA → ARDUINO STRING
  //
  // Giữ nguyên binary.
  // Không chuyển sang HEX để tiết kiệm kích thước.
  // ====================================================

  String manufacturerString(
    (char *)manufacturerData,
    sizeof(manufacturerData)
  );


  // ====================================================
  // 10. ADVERTISING DATA
  //
  // KHÔNG quảng bá UUID phòng.
  // Chỉ quảng bá encrypted token.
  // ====================================================

  BLEAdvertisementData advertisementData;


  advertisementData.setFlags(
    ESP_BLE_ADV_FLAG_GEN_DISC |
    ESP_BLE_ADV_FLAG_BREDR_NOT_SPT
  );


  advertisementData.setManufacturerData(
    manufacturerString
  );

  Serial.print("[BLE] Manufacturer Data Length: ");
  Serial.println(sizeof(manufacturerData));


  // ====================================================
  // 11. SCAN RESPONSE
  //
  // Chỉ chứa tên thiết bị.
  // Không chứa phòng.
  // ====================================================

  BLEAdvertisementData scanResponseData;


  scanResponseData.setName(
    DEVICE_NAME
  );


  // ====================================================
  // 12. APPLY ADVERTISING
  // ====================================================

  pAdvertising->setAdvertisementData(
    advertisementData
  );


  pAdvertising->setScanResponseData(
    scanResponseData
  );


  // ====================================================
  // 13. START BLE
  // ====================================================

  pAdvertising->start();


  // ====================================================
  // 14. SERIAL DEBUG
  // ====================================================

  Serial.println();
  Serial.println("========================================");
  Serial.println("[BLE] NEW SECURE TOKEN");
  Serial.println("========================================");


  Serial.print(
    "[BLE] Counter: "
  );

  Serial.println(
    counter
  );


  Serial.print(
    "[BLE] Device ID: "
  );

  printHex(
    (uint8_t *)&DEVICE_ID,
    4
  );


  Serial.print(
    "[BLE] Nonce: "
  );

  printHex(
    nonce,
    sizeof(nonce)
  );


  Serial.print(
    "[BLE] Ciphertext: "
  );

  printHex(
    ciphertext,
    sizeof(ciphertext)
  );


  Serial.print(
    "[BLE] Authentication Tag: "
  );

  printHex(
    tag,
    sizeof(tag)
  );


  Serial.print(
    "[BLE] Manufacturer Data: "
  );

  printHex(
    manufacturerData,
    sizeof(manufacturerData)
  );


  Serial.println(
    "[BLE] UUID THUC KHONG DUOC QUANG BA TRUC TIEP"
  );


  Serial.println(
    "[BLE] Token se thay doi sau 30 giay"
  );


  Serial.println(
    "========================================"
  );
}


// ======================================================
// PRINT HEX
// ======================================================

void printHex(
  const uint8_t *data,
  size_t len
) {

  for (
    size_t i = 0;
    i < len;
    i++
  ) {

    if (
      data[i] < 0x10
    ) {

      Serial.print(
        "0"
      );
    }


    Serial.print(
      data[i],
      HEX
    );


    if (
      i < len - 1
    ) {

      Serial.print(
        " "
      );
    }
  }


  Serial.println();
}