-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "LedgerDirection" AS ENUM ('CREDIT', 'DEBIT');

-- CreateEnum
CREATE TYPE "LedgerSource" AS ENUM ('ONBOARDING_GRANT', 'CREDIT_PACK', 'SUBSCRIPTION_GRANT', 'USAGE', 'APP_STORE_REVERSAL', 'ADMIN_ADJUSTMENT');

-- CreateEnum
CREATE TYPE "UsageKind" AS ENUM ('REALTIME_RESPONSE', 'REALTIME_TRANSCRIPTION', 'REALTIME_MINUTE_FLOOR', 'REASONING');

-- CreateEnum
CREATE TYPE "RealtimeSessionStatus" AS ENUM ('ACTIVE', 'ENDED', 'EXPIRED');

-- CreateTable
CREATE TABLE "Device" (
    "id" TEXT NOT NULL,
    "installId" TEXT NOT NULL,
    "attestKeyId" TEXT,
    "attestPublicKey" BYTEA,
    "attestCounter" INTEGER NOT NULL DEFAULT 0,
    "attestedAt" TIMESTAMP(3),
    "appAccountToken" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "blocked" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Device_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OnboardingGrant" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "installId" TEXT NOT NULL,
    "attestKeyHash" TEXT,
    "deviceCheckBits" TEXT,
    "credits" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OnboardingGrant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CreditLedgerEntry" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "direction" "LedgerDirection" NOT NULL,
    "source" "LedgerSource" NOT NULL,
    "amountMilli" BIGINT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "relatedId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CreditLedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UsageEvent" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "kind" "UsageKind" NOT NULL,
    "model" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "sessionId" TEXT,
    "inputTextTokens" INTEGER NOT NULL DEFAULT 0,
    "inputAudioTokens" INTEGER NOT NULL DEFAULT 0,
    "inputImageTokens" INTEGER NOT NULL DEFAULT 0,
    "cachedInputTokens" INTEGER NOT NULL DEFAULT 0,
    "outputTextTokens" INTEGER NOT NULL DEFAULT 0,
    "outputAudioTokens" INTEGER NOT NULL DEFAULT 0,
    "costMicrosUSD" BIGINT NOT NULL,
    "chargedMilli" BIGINT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UsageEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RealtimeSession" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "status" "RealtimeSessionStatus" NOT NULL DEFAULT 'ACTIVE',
    "secretExpiresAt" TIMESTAMP(3),
    "reservedMilli" BIGINT NOT NULL DEFAULT 0,
    "chargedMilli" BIGINT NOT NULL DEFAULT 0,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),

    CONSTRAINT "RealtimeSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppStoreTransaction" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT,
    "transactionId" TEXT NOT NULL,
    "originalTransactionId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "environment" TEXT NOT NULL,
    "purchaseDate" TIMESTAMP(3),
    "expiresDate" TIMESTAMP(3),
    "revocationDate" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppStoreTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Device_installId_key" ON "Device"("installId");

-- CreateIndex
CREATE UNIQUE INDEX "Device_attestKeyId_key" ON "Device"("attestKeyId");

-- CreateIndex
CREATE UNIQUE INDEX "Device_appAccountToken_key" ON "Device"("appAccountToken");

-- CreateIndex
CREATE UNIQUE INDEX "OnboardingGrant_deviceId_key" ON "OnboardingGrant"("deviceId");

-- CreateIndex
CREATE UNIQUE INDEX "OnboardingGrant_installId_key" ON "OnboardingGrant"("installId");

-- CreateIndex
CREATE UNIQUE INDEX "OnboardingGrant_attestKeyHash_key" ON "OnboardingGrant"("attestKeyHash");

-- CreateIndex
CREATE UNIQUE INDEX "CreditLedgerEntry_idempotencyKey_key" ON "CreditLedgerEntry"("idempotencyKey");

-- CreateIndex
CREATE INDEX "CreditLedgerEntry_deviceId_createdAt_idx" ON "CreditLedgerEntry"("deviceId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "UsageEvent_idempotencyKey_key" ON "UsageEvent"("idempotencyKey");

-- CreateIndex
CREATE INDEX "UsageEvent_deviceId_createdAt_idx" ON "UsageEvent"("deviceId", "createdAt");

-- CreateIndex
CREATE INDEX "RealtimeSession_deviceId_status_idx" ON "RealtimeSession"("deviceId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "AppStoreTransaction_transactionId_key" ON "AppStoreTransaction"("transactionId");

-- CreateIndex
CREATE INDEX "AppStoreTransaction_originalTransactionId_idx" ON "AppStoreTransaction"("originalTransactionId");

-- AddForeignKey
ALTER TABLE "CreditLedgerEntry" ADD CONSTRAINT "CreditLedgerEntry_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UsageEvent" ADD CONSTRAINT "UsageEvent_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RealtimeSession" ADD CONSTRAINT "RealtimeSession_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AppStoreTransaction" ADD CONSTRAINT "AppStoreTransaction_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE SET NULL ON UPDATE CASCADE;

