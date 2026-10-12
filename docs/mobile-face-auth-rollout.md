# Mobile-first face authentication

Android performs face landmarking, alignment and SFace embedding locally. A
camera image never reaches the attendance server. The request sent to the API
contains only a 128-number normalized vector, a one-use server nonce and an
ECDSA signature made with a private key held in Android Keystore.

The server work for one check-in is intentionally small: verify one P-256
signature, compare two 128-number vectors, and update PostgreSQL. This is the
path intended for the present small EC2 instance and approximately 50 students.
It does not require a Google Cloud account or a Play Console account.

## API flow

1. Student calls `POST /students/attendance/mobile-face-session` with the
   attendance session id. The API verifies that the class is open and returns a
   90-second `{sessionId, nonce, modelId}` ticket.
2. App captures one image, requires exactly one centered face, computes the
   embedding locally, requires an eyes-open then blink sequence, and signs
   `sessionId.nonce.modelId.sha256(JSON-vector)` with Android Keystore.
3. App calls `POST /students/attendance/mobile-face-session/complete` with the
   ticket id, nonce, vector, device public key and signature.
4. The API accepts only a public key previously enrolled for that student. It
   verifies the signature, consumes the ticket once, and stores `verified` or
   `failed` with the similarity score.
5. The normal `POST /students/attendance/scan` call uses
   `mobileFaceSessionId`, along with the existing BLE and GPS evidence. The
   mobile ticket is scoped to both the student and the attendance session, so it
   cannot be reused for a different class.

## Reference provisioning and device binding

`MobileFaceIdentity` is separate from the existing ArcFace `FaceIdentity`.
Vectors from the two models must never be compared. Create each mobile template
from 2--5 good, varied face images using the shipped SFace model and store only
the mean normalized vector. Do not keep arbitrary full camera uploads in the
attendance path.

Before enabling mobile authentication, use
`services/face_auth/tools/build_mobile_face_reference.py` on the 2--5 profile
photos already supplied by each student, then import its JSON output with
`npm run face:import-mobile-reference -- reference.json`. Photos remain in the
school's protected enrollment storage; only the normalized mean vector is
written to `MobileFaceIdentity`.

The first successful live face match binds the Android Keystore public key to
that student. It does not replace or learn the face template from the attendance
camera. Later attempts must use an active bound key. Students can list and
revoke their own keys through `/students/mobile-face-devices`.

Apply both Prisma migrations before setting `MOBILE_FACE_AUTH_ENABLED=true`.
Keep it `false` until templates exist for every pilot student.
The existing server-side ArcFace flow continues to operate while it is false.

Build the mobile-first client explicitly with
`--dart-define=MOBILE_FACE_AUTH=true`. Without that flag, the existing client
continues using its server-assisted path, which makes staged rollout reversible.

The old ArcFace container is not required by mobile attendance after the SFace
templates have been provisioned. The steady-state mobile-first command starts
PostgreSQL, NestJS and Caddy only.

## Operational limits

The profile arm64 APK measured 102.9 MB in this workspace. The face-model
assets are roughly 41 MB; a debug APK is intentionally much larger and is not
a size estimate for users. Build a signed arm64 release and measure that exact
artifact before distribution. Mobile devices still need enough RAM for one
112x112 SFace inference, while the EC2 no longer loads the recognition model
for a mobile check-in.
