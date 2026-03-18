export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  PRIVY_APP_ID: string;
  PRIVY_APP_SECRET: string;
  ADMIN_API_KEY: string;
  SERVICE_API_KEY: string;
  OPENAI_API_KEY: string;
  REDIS_URL: string;
  ENCRYPTION_KEY: string;
}

export interface Variables {
  userId: string;
  userEmail: string;
  isAdmin: boolean;
}

// Wallet types
export interface CreateWalletRequest {
  chain: "ethereum" | "solana" | "polygon";
  label?: string;
}

export interface CreateWalletResponse {
  walletId: string;
  address: string;
  chain: string;
  createdAt: string;
}

export interface TransferRequest {
  fromWalletId: string;
  toAddress: string;
  amount: string;
  token: string;
  chain: string;
  pin?: string;
}

export interface TransferResponse {
  transactionId: string;
  status: "pending" | "completed" | "failed";
  txHash?: string;
}

// Card types
export interface CreateCardRequest {
  walletId: string;
  cardType: "virtual" | "physical";
  spendingLimit: number;
  currency: "USD" | "EUR" | "GBP";
}

export interface CardResponse {
  cardId: string;
  last4: string;
  cardType: string;
  status: "active" | "frozen" | "cancelled";
  spendingLimit: number;
  currentSpend: number;
}

// Vault types
export interface DepositRequest {
  walletId: string;
  amount: string;
  lockDuration: "30d" | "90d" | "180d" | "365d";
}

export interface VaultResponse {
  vaultId: string;
  amount: string;
  apy: number;
  lockUntil: string;
  status: "active" | "matured" | "withdrawn";
}

// AI types
export interface ChatRequest {
  message: string;
  conversationId?: string;
  context?: "finance" | "support" | "general";
}

export interface ChatResponse {
  reply: string;
  conversationId: string;
  suggestedActions?: Array<{
    type: string;
    label: string;
    payload: Record<string, unknown>;
  }>;
}

// Admin types
export interface AdminUserResponse {
  userId: string;
  email: string;
  walletCount: number;
  totalBalance: string;
  kycStatus: "pending" | "verified" | "rejected";
  createdAt: string;
}

// Referral types
export interface CreateReferralRequest {
  code?: string;
}

export interface ReferralResponse {
  referralCode: string;
  referralCount: number;
  earnings: string;
  tier: "bronze" | "silver" | "gold" | "platinum";
}

// Notification types
export interface NotificationPreferences {
  email: boolean;
  push: boolean;
  sms: boolean;
  categories: {
    transactions: boolean;
    security: boolean;
    marketing: boolean;
    rewards: boolean;
  };
}
