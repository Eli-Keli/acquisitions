import bcrypt from 'bcrypt';
import logger from '#config/logger.js';
import { eq } from 'drizzle-orm';
import { db } from '#config/database.js';
import { users } from '#models/user.model.js';

export const hashPassword = async (password) => {
  try {
    return bcrypt.hash(password, 10);
  } catch (error) {
    logger.error(`Error hashing the password: ${error}`);
    throw new Error('Error hashing password', { cause: error });
  }
};

export const comparePassword = async (plainPassword, hashedPassword) => {
  try {
    return bcrypt.compare(plainPassword, hashedPassword);
  } catch (error) {
    logger.error(`Error comparing password: ${error}`);
    throw new Error('Error validating password', { cause: error });
  }
};

export const createUser = async ({ name, email, password, role = 'user'}) => {
  try {
    const existingUser = await db.select().from(users).where(eq(users.email, email)).limit(1);

    if (existingUser.length > 0) throw new Error('User with this email already exists');

    const hashedPassword = await hashPassword(password);

    const [newUser] = await db
      .insert(users)
      .values({ name, email, password: hashedPassword, role })
      .returning({ 
        id: users.id, 
        name: users.name, 
        email: users.email,
        role: users.role,
        created_at: users.created_at 
      });

    logger.info(`User ${newUser.email} created successfully`);
    return newUser;
  } catch (error) {
    logger.error(`Error creating the user: ${error}`);
    throw error;
  }
};

export const authenticateUser = async ({ email, password }) => {
  try {
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.email, email))
      .limit(1);

    if (!user) throw new Error('User not found');

    const isPasswordValid = await comparePassword(password, user.password);
    if (!isPasswordValid) throw new Error('Invalid email or password');

    return user;
  } catch (error) {
    logger.error(`Error authenticating user: ${error}`);
    throw error;
  }
};