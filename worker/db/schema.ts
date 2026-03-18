import { sqliteTable, text, integer, real } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull(),
  status: text("status").default("active"), // active, frozen
  freezeReason: text("freeze_reason"),
  kycStatus: text("kyc_status").default("pending"), // pending, verified, rejected
  pinHash: text("pin_hash"),
  createdAt: text("created_at").notNull(),
  updatedAt: text("updated_at"),
});

export const wallets = sqliteTable("wallets", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  address: text("address").notNull(),
  chain: text("chain").notNull(), // ethereum, solana, polygon
  label: text("label"),
  deletedAt: text("deleted_at"),
  createdAt: text("created_at").notNull(),
});

export const transactions = sqliteTable("transactions", {
  id: text("id").primaryKey(),
  walletId: text("wallet_id").notNull().references(() => wallets.id),
  toAddress: text("to_address").notNull(),
  amount: text("amount").notNull(),
  token: text("token").notNull(),
  chain: text("chain"),
  status: text("status").default("pending"), // pending, completed, failed
  txHash: text("tx_hash"),
  createdAt: text("created_at").notNull(),
});

export const cards = sqliteTable("cards", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  walletId: text("wallet_id").notNull().references(() => wallets.id),
  last4: text("last4").notNull(),
  cardType: text("card_type").notNull(), // virtual, physical
  status: text("status").default("active"), // active, frozen, cancelled
  spendingLimit: real("spending_limit").notNull(),
  currentSpend: real("current_spend").default(0),
  currency: text("currency").default("USD"),
  createdAt: text("created_at").notNull(),
  updatedAt: text("updated_at"),
});

export const cardTransactions = sqliteTable("card_transactions", {
  id: text("id").primaryKey(),
  cardId: text("card_id").notNull().references(() => cards.id),
  merchantName: text("merchant_name"),
  amount: real("amount").notNull(),
  currency: text("currency").default("USD"),
  status: text("status").default("completed"),
  createdAt: text("created_at").notNull(),
});

export const vaults = sqliteTable("vaults", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  walletId: text("wallet_id").notNull().references(() => wallets.id),
  amount: text("amount").notNull(),
  apy: real("apy").notNull(),
  lockUntil: text("lock_until").notNull(),
  status: text("status").default("active"), // active, matured, withdrawn
  withdrawnAt: text("withdrawn_at"),
  createdAt: text("created_at").notNull(),
});

export const chatMessages = sqliteTable("chat_messages", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  conversationId: text("conversation_id").notNull(),
  role: text("role").notNull(), // user, assistant
  content: text("content").notNull(),
  createdAt: text("created_at").notNull(),
});

export const referrals = sqliteTable("referrals", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  code: text("code").notNull().unique(),
  earnings: text("earnings").default("0.00"),
  createdAt: text("created_at").notNull(),
});

export const referralUses = sqliteTable("referral_uses", {
  id: text("id").primaryKey(),
  referralId: text("referral_id").notNull().references(() => referrals.id),
  referredUserId: text("referred_user_id").notNull().references(() => users.id),
  createdAt: text("created_at").notNull(),
});

export const notifications = sqliteTable("notifications", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id),
  title: text("title").notNull(),
  message: text("message").notNull(),
  category: text("category").notNull(), // transactions, security, marketing, rewards
  data: text("data"), // JSON
  readAt: text("read_at"),
  createdAt: text("created_at").notNull(),
});

export const notificationPreferences = sqliteTable("notification_preferences", {
  userId: text("user_id").primaryKey().references(() => users.id),
  email: integer("email").default(1),
  push: integer("push").default(1),
  sms: integer("sms").default(0),
  categories: text("categories"), // JSON
  updatedAt: text("updated_at"),
});

export const auditLog = sqliteTable("audit_log", {
  id: text("id").primaryKey(),
  userId: text("user_id"),
  action: text("action").notNull(),
  resource: text("resource").notNull(),
  details: text("details"), // JSON
  ipAddress: text("ip_address"),
  createdAt: text("created_at").notNull(),
});
