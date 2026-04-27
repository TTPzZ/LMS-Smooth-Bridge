import mongoose, { InferSchemaType, Model } from 'mongoose';

const notificationEventSchema = new mongoose.Schema(
    {
        dedupeKey: {
            type: String,
            required: true,
            unique: true,
            index: true
        },
        token: {
            type: String,
            required: true,
            index: true
        },
        stage: {
            type: String,
            enum: ['UPCOMING', 'OPEN', 'COMMENT_PENDING_NOON'],
            required: true
        },
        classId: {
            type: String,
            required: true
        },
        slotId: {
            type: String,
            required: true
        },
        attendanceOpenAt: {
            type: Date,
            required: true
        },
        status: {
            type: String,
            enum: ['PENDING', 'SENT'],
            default: 'PENDING',
            required: true
        },
        error: {
            type: String,
            default: null
        },
        expiresAt: {
            type: Date,
            required: true
        }
    },
    {
        timestamps: true,
        versionKey: false
    }
);

notificationEventSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export type NotificationEventDocument = InferSchemaType<typeof notificationEventSchema>;
export type NotificationEventModel = Model<NotificationEventDocument>;

export const NotificationEvent = (mongoose.models.NotificationEvent as NotificationEventModel)
    || mongoose.model<NotificationEventDocument>('NotificationEvent', notificationEventSchema);
