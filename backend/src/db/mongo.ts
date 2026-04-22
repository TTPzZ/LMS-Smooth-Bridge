import mongoose from 'mongoose';
import { env } from '../config/env';

let mongoConnected = false;

export async function connectMongo(): Promise<void> {
    if (mongoConnected) {
        return;
    }

    if (!env.MONGO_URI) {
        throw new Error('Missing MONGO_URI in backend/.env');
    }

    await mongoose.connect(env.MONGO_URI, {
        dbName: env.MONGO_DB_NAME || undefined
    });
    mongoConnected = true;
}

export async function disconnectMongo(): Promise<void> {
    if (!mongoConnected) {
        return;
    }

    await mongoose.disconnect();
    mongoConnected = false;
}
