import mongoose, { InferSchemaType, Model } from 'mongoose';

const deviceSchema = new mongoose.Schema(
    {
        token: {
            type: String,
            required: true,
            unique: true,
            index: true,
            trim: true
        },
        platform: {
            type: String,
            required: true,
            default: 'unknown',
            trim: true
        },
        userId: {
            type: String,
            default: null
        },
        timezone: {
            type: String,
            default: null
        },
        appVersion: {
            type: String,
            default: null
        },
        lastSeenAt: {
            type: Date,
            required: true
        }
    },
    {
        timestamps: true,
        versionKey: false
    }
);

export type DeviceDocument = InferSchemaType<typeof deviceSchema>;
export type DeviceModel = Model<DeviceDocument>;

export const Device = (mongoose.models.Device as DeviceModel)
    || mongoose.model<DeviceDocument>('Device', deviceSchema);
